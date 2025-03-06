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
