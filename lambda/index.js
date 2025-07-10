const AWS = require('aws-sdk');

// Configure AWS SDK
const dynamodb = new AWS.DynamoDB.DocumentClient();
const TABLE_NAME = process.env.TABLE_NAME;
const COUNTER_ID = 'visitor-count';

/**
 * Lambda function to handle visitor counter
 * @param {Object} event - API Gateway event
 * @param {Object} context - Lambda context
 * @returns {Object} API Gateway response
 */
exports.handler = async (event, context) => {
    console.log('Event:', JSON.stringify(event, null, 2));
    
    try {
        // Get current visitor count
        const currentCount = await getVisitorCount();
        
        // Increment and update count
        const newCount = await incrementVisitorCount(currentCount);
        
        // Return success response
        return createResponse(200, {
            count: newCount,
            message: 'Visitor count updated successfully',
            timestamp: new Date().toISOString()
        });
        
    } catch (error) {
        console.error('Error in visitor counter:', error);
        
        return createResponse(500, {
            error: 'Internal server error',
            message: error.message,
            timestamp: new Date().toISOString()
        });
    }
};

/**
 * Get current visitor count from DynamoDB
 * @returns {Promise<number>} Current visitor count
 */
async function getVisitorCount() {
    const params = {
        TableName: TABLE_NAME,
        Key: { id: COUNTER_ID }
    };
    
    try {
        const result = await dynamodb.get(params).promise();
        return result.Item ? result.Item.count : 0;
    } catch (error) {
        console.error('Error getting visitor count:', error);
        throw error;
    }
}

/**
 * Increment visitor count in DynamoDB
 * @param {number} currentCount - Current visitor count
 * @returns {Promise<number>} New visitor count
 */
async function incrementVisitorCount(currentCount) {
    const newCount = currentCount + 1;
    
    const params = {
        TableName: TABLE_NAME,
        Key: { id: COUNTER_ID },
        UpdateExpression: 'SET #count = :count, #updated = :updated',
        ExpressionAttributeNames: {
            '#count': 'count',
            '#updated': 'updated_at'
        },
        ExpressionAttributeValues: {
            ':count': newCount,
            ':updated': new Date().toISOString()
        }
    };
    
    try {
        await dynamodb.update(params).promise();
        return newCount;
    } catch (error) {
        console.error('Error updating visitor count:', error);
        throw error;
    }
}

/**
 * Create API Gateway response
 * @param {number} statusCode - HTTP status code
 * @param {Object} body - Response body
 * @returns {Object} API Gateway response
 */
function createResponse(statusCode, body) {
    return {
        statusCode: statusCode,
        headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(body)
    };
} 