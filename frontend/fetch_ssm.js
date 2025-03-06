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
