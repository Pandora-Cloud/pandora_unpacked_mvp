#!/bin/bash

# Ensure script runs from its own directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || { echo "Failed to change to script directory"; exit 1; }

# Create frontend directories
for dir in frontend/js frontend/css; do
  mkdir -p "$dir" || { echo "Failed to create directory $dir"; exit 1; }
done

# Create index.html (Login Page)
cat > frontend/index.html << 'EOF' || { echo "Failed to create frontend/index.html"; exit 1; }
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Chatbot MVP - Login</title>
    <link rel="stylesheet" href="css/styles.css">
    <!-- AWS Amplify for authentication -->
    <script src="https://unpkg.com/aws-amplify@5.0.0/dist/aws-amplify.min.js"></script>
    <!-- Load env.js for Cognito config -->
    <script src="js/env.js"></script>
    <script src="js/auth.js"></script>
</head>
<body>
    <div id="login-container">
        <h1>Login</h1>
        <input type="email" id="email" placeholder="Email">
        <input type="password" id="password" placeholder="Password">
        <button onclick="login()">Login</button>
        <p id="login-error" style="color: red;"></p>
    </div>
</body>
</html>
EOF

# Create chat.html (Chat Interface)
cat > frontend/chat.html << 'EOF' || { echo "Failed to create frontend/chat.html"; exit 1; }
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Chatbot MVP - Chat</title>
    <link rel="stylesheet" href="css/styles.css">
    <!-- AWS Amplify for authentication -->
    <script src="https://unpkg.com/aws-amplify@5.0.0/dist/aws-amplify.min.js"></script>
    <!-- Load env.js for Cognito config -->
    <script src="js/env.js"></script>
    <script src="js/auth.js"></script>
    <script src="js/chat.js"></script>
</head>
<body>
    <div id="chat-container">
        <h1>Chat</h1>
        <select id="llm">
            <option value="titan-text-express-v1">Titan Text Express</option>
        </select>
        <div id="chat-history"></div>
        <input type="text" id="message" placeholder="Type a message">
        <button onclick="sendMessage()">Send</button>
        <button onclick="logout()">Logout</button>
        <p id="chat-error" style="color: red;"></p>
    </div>
    <script>
        // Redirect to login if not authenticated
        if (!localStorage.getItem('idToken')) {
            window.location.href = 'index.html';
        }
    </script>
</body>
</html>
EOF

# Create js/env.js (Placeholder, populated later)
cat > frontend/js/env.js << 'EOF' || { echo "Failed to create frontend/js/env.js"; exit 1; }
// This will be populated by fetch_ssm.js
window.REACT_APP_USER_POOL_ID = "";
window.REACT_APP_CLIENT_ID = "";
window.REACT_APP_IDENTITY_POOL_ID = "";
EOF

# Create js/auth.js (Authentication Logic)
cat > frontend/js/auth.js << 'EOF' || { echo "Failed to create frontend/js/auth.js"; exit 1; }
// Configure Amplify with Cognito details
Amplify.configure({
    Auth: {
        region: 'us-west-2',
        userPoolId: window.REACT_APP_USER_POOL_ID,
        userPoolWebClientId: window.REACT_APP_CLIENT_ID,
        identityPoolId: window.REACT_APP_IDENTITY_POOL_ID
    }
});

// Login function
async function login() {
    const email = document.getElementById('email').value;
    const password = document.getElementById('password').value;
    const errorElement = document.getElementById('login-error');

    try {
        const user = await Auth.signIn(email, password);
        const idToken = user.signInUserSession.idToken.jwtToken;
        localStorage.setItem('idToken', idToken);
        window.location.href = 'chat.html';
    } catch (error) {
        errorElement.textContent = 'Login failed: ' + error.message;
    }
}

// Logout function
async function logout() {
    try {
        await Auth.signOut();
        localStorage.removeItem('idToken');
        window.location.href = 'index.html';
    } catch (error) {
        document.getElementById('chat-error').textContent = 'Logout failed: ' + error.message;
    }
}
EOF

# Create js/chat.js (Chat Logic)
cat > frontend/js/chat.js << 'EOF' || { echo "Failed to create frontend/js/chat.js"; exit 1; }
async function sendMessage() {
    const message = document.getElementById('message').value;
    const llm = document.getElementById('llm').value;
    const sessionId = Date.now().toString(); // Simple session ID
    const errorElement = document.getElementById('chat-error');
    const historyElement = document.getElementById('chat-history');
    const idToken = localStorage.getItem('idToken');

    if (!message) {
        errorElement.textContent = 'Please enter a message';
        return;
    }

    try {
        const response = await fetch(`https://chat.pandoracloud.net/chat/${sessionId}`, {
            method: 'POST',
            headers: {
                'Authorization': idToken,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ message, llm, sessionId })
        });

        if (response.status === 429) {
            errorElement.textContent = 'Too many requests, please wait.';
            return;
        }

        const data = await response.json();
        if (!response.ok) {
            throw new Error(data.error || 'Chat request failed');
        }

        const messageDiv = document.createElement('div');
        messageDiv.textContent = `You: ${message}`;
        historyElement.appendChild(messageDiv);

        const responseDiv = document.createElement('div');
        responseDiv.textContent = `Bot: ${data.response}`;
        historyElement.appendChild(responseDiv);

        document.getElementById('message').value = '';
        errorElement.textContent = '';
    } catch (error) {
        errorElement.textContent = 'Error: ' + error.message;
    }
}
EOF

# Create css/styles.css (Basic Styling)
cat > frontend/css/styles.css << 'EOF' || { echo "Failed to create frontend/css/styles.css"; exit 1; }
body {
    font-family: Arial, sans-serif;
    margin: 0;
    padding: 20px;
    background-color: #f0f0f0;
}

#login-container, #chat-container {
    max-width: 600px;
    margin: 0 auto;
    background: white;
    padding: 20px;
    border-radius: 5px;
    box-shadow: 0 0 10px rgba(0,0,0,0.1);
}

input, select, button {
    display: block;
    width: 100%;
    margin: 10px 0;
    padding: 8px;
}

button {
    background-color: #007bff;
    color: white;
    border: none;
    cursor: pointer;
}

button:hover {
    background-color: #0056b3;
}

#chat-history {
    max-height: 300px;
    overflow-y: auto;
    margin: 10px 0;
    padding: 10px;
    background: #f9f9f9;
}
EOF

# Create fetch_ssm.js (Using AWS SDK v3)
cat > frontend/fetch_ssm.js << 'EOF' || { echo "Failed to create frontend/fetch_ssm.js"; exit 1; }
const { SSMClient, GetParametersCommand } = require('@aws-sdk/client-ssm');
const fs = require('fs');

const client = new SSMClient({ region: 'us-west-2' });

async function fetchSSMParams() {
    const command = new GetParametersCommand({
        Names: [
            '/chatbot-mvp/cognito-identity-pool-id',
            '/chatbot-mvp/cognito-user-pool-id',
            '/chatbot-mvp/cognito-client-id'
        ],
        WithDecryption: true
    });

    const response = await client.send(command);
    const ssmValues = {};
    response.Parameters.forEach(param => {
        const name = param.Name.split('/').pop();
        ssmValues[name] = param.Value;
    });

    const envContent = `
        window.REACT_APP_IDENTITY_POOL_ID = "${ssmValues['cognito-identity-pool-id']}";
        window.REACT_APP_USER_POOL_ID = "${ssmValues['cognito-user-pool-id']}";
        window.REACT_APP_CLIENT_ID = "${ssmValues['cognito-client-id']}";
    `;
    fs.writeFileSync('js/env.js', envContent);
    console.log('env.js updated with SSM parameters');
}

fetchSSMParams().catch(console.error);
EOF

# Initialize npm and install AWS SDK v3 for fetch_ssm.js
cd frontend || { echo "Failed to change to frontend directory"; exit 1; }
npm init -y > /dev/null 2>&1 || { echo "Failed to initialize npm"; exit 1; }
npm install @aws-sdk/client-ssm || { echo "Failed to install @aws-sdk/client-ssm"; exit 1; }

echo "Frontend files created successfully in frontend/!"
echo "Next steps:"
echo "1. Configure AWS credentials with 'aws configure' if not already done."
echo "2. Run 'node frontend/fetch_ssm.js' to populate frontend/js/env.js with SSM parameters."
echo "3. Test locally with 'python3 -m http.server 8000' from frontend/ directory."
echo "4. Deploy with 'aws s3 sync frontend/ s3://chatbot-mvp-frontend/ --region us-west-2'."
