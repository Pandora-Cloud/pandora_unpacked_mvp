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
