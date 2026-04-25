#!/bin/bash
set -e

# Update system
yum update -y

# Install dependencies
yum install -y python3 python3-pip mysql git

# Install Python packages
pip3 install flask pymysql boto3

# Create application directory
mkdir -p /opt/vulnerable-app
cd /opt/vulnerable-app

# Create vulnerable Flask application
cat > app.py << 'PYTHON_APP'
from flask import Flask, request, render_template_string, session, redirect, url_for
import pymysql
import boto3
import os
import pickle
import base64

app = Flask(__name__)

# VULNERABILITY: Hardcoded secret key
app.secret_key = 'super-secret-key-12345'

# VULNERABILITY: Database credentials in code
DB_HOST = '${db_endpoint}'.split(':')[0]
DB_USER = '${db_username}'
DB_PASS = '${db_password}'
DB_NAME = '${db_name}'
BUCKET_NAME = '${bucket_name}'

# VULNERABILITY: Hardcoded AWS credentials (simulated)
AWS_ACCESS_KEY = 'AKIAIOSFODNN7EXAMPLE'
AWS_SECRET_KEY = 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'

def get_db_connection():
    # VULNERABILITY: No SSL/TLS for database connection
    return pymysql.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASS,
        database=DB_NAME
    )

@app.route('/')
def index():
    return render_template_string('''
        <html>
        <head>
            <title>Vulnerable Demo App</title>
            <style>
                body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; background: #f5f5f5; }
                h1 { color: #d32f2f; }
                h2, h3 { color: #333; }
                a { color: #1976d2; text-decoration: none; }
                a:hover { text-decoration: underline; }
                ul { line-height: 1.8; }
                pre { background: #fff; padding: 15px; border-left: 4px solid #d32f2f; overflow-x: auto; }
                .container { background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
            </style>
        </head>
        <body>
            <div class="container">
            <h1>⚠️ Vulnerable Demo Application</h1>
            <p>This application is intentionally vulnerable for AWS Security Agent demonstration.</p>
            
            <h2>Features:</h2>
            <ul>
                <li><a href="/search">Search Users</a></li>
                <li><a href="/login">Login</a></li>
                <li><a href="/profile">View Profile</a></li>
                <li><a href="/upload">Upload File</a></li>
                <li><a href="/api/users">API - List Users</a></li>
            </ul>
            
            <h3>Debug Info (VULNERABILITY: Information Disclosure)</h3>
            <pre>
Database: ''' + DB_HOST + '''
AWS Bucket: ''' + BUCKET_NAME + '''
AWS Key: ''' + AWS_ACCESS_KEY + '''
            </pre>
            </div>
        </body>
        </html>
    ''')

@app.route('/search')
def search():
    query = request.args.get('q', '')
    
    if query:
        # VULNERABILITY: SQL Injection
        conn = get_db_connection()
        cursor = conn.cursor()
        sql = f"SELECT * FROM users WHERE username LIKE '%%{query}%%'"
        cursor.execute(sql)
        results = cursor.fetchall()
        cursor.close()
        conn.close()
        
        # VULNERABILITY: XSS - Unescaped output
        output = f"<h2>Search Results for: {query}</h2><ul>"
        for row in results:
            output += f"<li>{row[1]} - {row[2]}</li>"
        output += "</ul>"
    else:
        output = "<p>Enter a search term</p>"
    
    return render_template_string('''
        <html>
        <body>
            <h1>User Search</h1>
            <form action="/search" method="get">
                <input type="text" name="q" placeholder="Search users...">
                <button type="submit">Search</button>
            </form>
            ''' + output + '''
            <br><a href="/">Back to Home</a>
        </body>
        </html>
    ''')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        # VULNERABILITY: SQL Injection in authentication
        conn = get_db_connection()
        cursor = conn.cursor()
        sql = f"SELECT * FROM users WHERE username='{username}' AND password='{password}'"
        cursor.execute(sql)
        user = cursor.fetchone()
        cursor.close()
        conn.close()
        
        if user:
            # VULNERABILITY: Session token in URL
            session['user_id'] = user[0]
            return redirect(f'/profile?token={user[0]}')
        else:
            # VULNERABILITY: Verbose error message
            return f"Login failed for user: {username}. Database query: {sql}"
    
    return render_template_string('''
        <html>
        <body>
            <h1>Login</h1>
            <form method="post">
                <input type="text" name="username" placeholder="Username"><br>
                <input type="password" name="password" placeholder="Password"><br>
                <button type="submit">Login</button>
            </form>
            <br><a href="/">Back to Home</a>
        </body>
        </html>
    ''')

@app.route('/profile')
def profile():
    # VULNERABILITY: Insecure Direct Object Reference
    user_id = request.args.get('token', session.get('user_id'))
    
    if not user_id:
        return redirect('/login')
    
    # VULNERABILITY: No authorization check
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute(f"SELECT * FROM users WHERE id={user_id}")
    user = cursor.fetchone()
    cursor.close()
    conn.close()
    
    if user:
        return render_template_string('''
            <html>
            <body>
                <h1>User Profile</h1>
                <p>ID: ''' + str(user[0]) + '''</p>
                <p>Username: ''' + str(user[1]) + '''</p>
                <p>Email: ''' + str(user[2]) + '''</p>
                <p>SSN: ''' + str(user[3]) + '''</p>
                <br><a href="/">Back to Home</a>
            </body>
            </html>
        ''')
    return "User not found"

@app.route('/upload', methods=['GET', 'POST'])
def upload():
    if request.method == 'POST':
        # VULNERABILITY: No file type validation
        file = request.files.get('file')
        if file:
            # VULNERABILITY: Path traversal
            filename = request.form.get('filename', file.filename)
            file.save(f'/tmp/{filename}')
            return f"File uploaded: {filename}"
    
    return render_template_string('''
        <html>
        <body>
            <h1>File Upload</h1>
            <form method="post" enctype="multipart/form-data">
                <input type="file" name="file"><br>
                <input type="text" name="filename" placeholder="Custom filename (optional)"><br>
                <button type="submit">Upload</button>
            </form>
            <br><a href="/">Back to Home</a>
        </body>
        </html>
    ''')

@app.route('/api/users')
def api_users():
    # VULNERABILITY: No authentication required for API
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT id, username, email, ssn FROM users")
    users = cursor.fetchall()
    cursor.close()
    conn.close()
    
    # VULNERABILITY: Sensitive data exposure
    return {'users': [{'id': u[0], 'username': u[1], 'email': u[2], 'ssn': u[3]} for u in users]}

@app.route('/deserialize')
def deserialize():
    # VULNERABILITY: Insecure deserialization
    data = request.args.get('data')
    if data:
        try:
            obj = pickle.loads(base64.b64decode(data))
            return f"Deserialized: {obj}"
        except Exception as e:
            # VULNERABILITY: Verbose error messages
            return f"Error: {str(e)}"
    return "Provide data parameter"

@app.route('/fetch')
def fetch():
    # VULNERABILITY: Server-Side Request Forgery (SSRF)
    url = request.args.get('url')
    if url:
        import urllib.request
        try:
            response = urllib.request.urlopen(url)
            return response.read()
        except Exception as e:
            return f"Error fetching URL: {str(e)}"
    return "Provide url parameter"

# VULNERABILITY: Debug mode enabled in production
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80, debug=True)
PYTHON_APP

# Initialize database
cat > init_db.py << 'PYTHON_INIT'
import pymysql
import time

DB_HOST = '${db_endpoint}'.split(':')[0]
DB_USER = '${db_username}'
DB_PASS = '${db_password}'
DB_NAME = '${db_name}'

# Wait for database to be ready
time.sleep(30)

conn = pymysql.connect(host=DB_HOST, user=DB_USER, password=DB_PASS, database=DB_NAME)
cursor = conn.cursor()

# Create users table
cursor.execute('''
    CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50),
        email VARCHAR(100),
        ssn VARCHAR(11),
        password VARCHAR(50)
    )
''')

# Insert sample data with sensitive information
cursor.execute('''
    INSERT INTO users (username, email, ssn, password) VALUES
    ('admin', 'admin@example.com', '123-45-6789', 'admin123'),
    ('john', 'john@example.com', '987-65-4321', 'password'),
    ('jane', 'jane@example.com', '555-12-3456', 'qwerty')
''')

conn.commit()
cursor.close()
conn.close()
print("Database initialized successfully")
PYTHON_INIT

# Initialize database
python3 init_db.py

# Create systemd service
cat > /etc/systemd/system/vulnerable-app.service << 'SERVICE'
[Unit]
Description=Vulnerable Demo Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/vulnerable-app
ExecStart=/usr/bin/python3 /opt/vulnerable-app/app.py
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

# Start the application
systemctl daemon-reload
systemctl enable vulnerable-app
systemctl start vulnerable-app

echo "Vulnerable application deployed successfully!"
