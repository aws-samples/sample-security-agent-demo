"""
Unit tests for the Lambda function's Bedrock Converse API integration.

Verifies that:
- generate_terraform_code calls bedrock.converse (not invoke_model)
- The request/response format matches the Converse API contract
- The function returns the same (text, target_file, file_sha) tuple
- lambda_handler end-to-end flow works with the new API
"""

import json
import os
import unittest
from unittest.mock import patch, MagicMock

# Set required env vars before importing the module
os.environ.setdefault('BEDROCK_MODEL_ID', 'us.anthropic.claude-sonnet-5')
os.environ.setdefault('CONTEXT_BUCKET', 'test-bucket')
os.environ.setdefault('GITHUB_TOKEN', 'fake-token')
os.environ.setdefault('GITHUB_OWNER', 'test-owner')
os.environ.setdefault('GITHUB_REPO', 'test-repo')

import lambda_function


class TestConverseAPIIntegration(unittest.TestCase):
    """Tests for the Bedrock Converse API migration."""

    def _mock_converse_response(self, text='resource "aws_instance" "example" {}'):
        """Build a mock response matching the Converse API shape."""
        return {
            'output': {
                'message': {
                    'role': 'assistant',
                    'content': [{'text': text}],
                }
            },
            'stopReason': 'end_turn',
            'usage': {'inputTokens': 100, 'outputTokens': 50},
        }

    @patch.object(lambda_function, 'get_relevant_terraform_files', return_value={})
    @patch.object(lambda_function, 'bedrock')
    def test_converse_called_with_correct_format(self, mock_bedrock, mock_files):
        """Verify converse is called with the right message structure."""
        mock_bedrock.converse.return_value = self._mock_converse_response()

        lambda_function.generate_terraform_code('create a new EC2 instance', {})

        mock_bedrock.converse.assert_called_once()
        call_kwargs = mock_bedrock.converse.call_args[1]

        # Verify Converse API structure
        self.assertEqual(call_kwargs['modelId'], os.environ['BEDROCK_MODEL_ID'])
        self.assertEqual(len(call_kwargs['messages']), 1)
        self.assertEqual(call_kwargs['messages'][0]['role'], 'user')
        self.assertIn('text', call_kwargs['messages'][0]['content'][0])
        self.assertEqual(call_kwargs['inferenceConfig']['maxTokens'], 2000)

    @patch.object(lambda_function, 'get_relevant_terraform_files', return_value={})
    @patch.object(lambda_function, 'bedrock')
    def test_invoke_model_not_used(self, mock_bedrock, mock_files):
        """Verify invoke_model is NOT called (old API removed)."""
        mock_bedrock.converse.return_value = self._mock_converse_response()

        lambda_function.generate_terraform_code('create a VPC', {})

        mock_bedrock.invoke_model.assert_not_called()

    @patch.object(lambda_function, 'get_relevant_terraform_files', return_value={})
    @patch.object(lambda_function, 'bedrock')
    def test_return_tuple_contract(self, mock_bedrock, mock_files):
        """Verify the function still returns (text, target_file, file_sha)."""
        expected_code = 'resource "aws_vpc" "main" { cidr_block = "10.0.0.0/16" }'
        mock_bedrock.converse.return_value = self._mock_converse_response(expected_code)

        result = lambda_function.generate_terraform_code('create a VPC', {})

        self.assertIsInstance(result, tuple)
        self.assertEqual(len(result), 3)
        text, target_file, file_sha = result
        self.assertEqual(text, expected_code)
        self.assertIsInstance(target_file, str)
        self.assertTrue(target_file.endswith('.tf'))

    @patch.object(lambda_function, 'get_relevant_terraform_files', return_value={})
    @patch.object(lambda_function, 'bedrock')
    def test_no_anthropic_version_in_request(self, mock_bedrock, mock_files):
        """Verify no Anthropic-specific fields leak into the Converse call."""
        mock_bedrock.converse.return_value = self._mock_converse_response()

        lambda_function.generate_terraform_code('create an S3 bucket', {})

        call_kwargs = mock_bedrock.converse.call_args[1]
        # Converse API should not have anthropic_version or body fields
        self.assertNotIn('body', call_kwargs)
        self.assertNotIn('anthropic_version', str(call_kwargs))

    @patch.object(lambda_function, 'create_github_pr', return_value='https://github.com/test/pr/1')
    @patch.object(lambda_function, 'get_relevant_terraform_files', return_value={})
    @patch.object(lambda_function, 'get_s3_context', return_value={'Environment': 'dev'})
    @patch.object(lambda_function, 'bedrock')
    def test_lambda_handler_end_to_end(self, mock_bedrock, mock_s3, mock_files, mock_pr):
        """Verify the full handler flow works with the Converse API."""
        mock_bedrock.converse.return_value = self._mock_converse_response('resource "aws_instance" "web" {}')

        event = {
            'body': json.dumps({'request': 'create an EC2 instance'}),
        }
        response = lambda_function.lambda_handler(event, None)

        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertEqual(body['status'], 'success')
        self.assertIn('terraform_code', body)
        self.assertIn('pr_url', body)

    @patch.object(lambda_function, 'get_relevant_blocks_for_update')
    @patch.object(lambda_function, 'bedrock')
    def test_update_operation_with_converse(self, mock_bedrock, mock_blocks):
        """Verify UPDATE operations also use the Converse API correctly."""
        mock_blocks.return_value = {
            'full_content': 'resource "aws_instance" "web" { instance_type = "t2.micro" }',
            'relevant_blocks': ['resource "aws_instance" "web" { instance_type = "t2.micro" }'],
            'file_sha': 'abc123',
        }
        mock_bedrock.converse.return_value = self._mock_converse_response(
            'resource "aws_instance" "web" { instance_type = "t3.medium" }'
        )

        text, target_file, file_sha = lambda_function.generate_terraform_code(
            'update the instance type to t3.medium', {}
        )

        mock_bedrock.converse.assert_called_once()
        self.assertEqual(file_sha, 'abc123')
        self.assertIn('t3.medium', text)


if __name__ == '__main__':
    unittest.main()
