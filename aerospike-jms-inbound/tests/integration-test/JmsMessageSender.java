import javax.jms.*;
import com.rabbitmq.jms.admin.RMQConnectionFactory;
import java.util.Properties;

/**
 * Simple JMS Message Sender for RabbitMQ
 * Sends a TextMessage to a RabbitMQ queue using JMS API
 */
public class JmsMessageSender {
    public static void main(String[] args) {
        if (args.length != 4) {
            System.err.println("Usage: java JmsMessageSender <host> <port> <username> <password> <queue> <message>");
            System.exit(1);
        }
        
        String host = args[0];
        int port = Integer.parseInt(args[1]);
        String username = args[2];
        String password = args[3];
        String queueName = args[4];
        String messageText = args[5];
        
        Connection connection = null;
        Session session = null;
        MessageProducer producer = null;
        
        try {
            // Create RabbitMQ JMS ConnectionFactory
            RMQConnectionFactory connectionFactory = new RMQConnectionFactory();
            connectionFactory.setHost(host);
            connectionFactory.setPort(port);
            connectionFactory.setUsername(username);
            connectionFactory.setPassword(password);
            
            // Create connection
            connection = connectionFactory.createConnection();
            connection.start();
            
            // Create session (non-transacted, auto-acknowledge)
            session = connection.createSession(false, Session.AUTO_ACKNOWLEDGE);
            
            // Create queue destination
            Queue queue = session.createQueue(queueName);
            
            // Create producer
            producer = session.createProducer(queue);
            
            // Create TextMessage with JSON content
            TextMessage message = session.createTextMessage(messageText);
            
            // Send message
            producer.send(message);
            
            System.out.println("SUCCESS: Message sent to queue: " + queueName);
            System.out.println("Message content: " + messageText);
            
        } catch (Exception e) {
            System.err.println("ERROR: Failed to send message");
            e.printStackTrace();
            System.exit(1);
        } finally {
            // Clean up resources
            try {
                if (producer != null) producer.close();
                if (session != null) session.close();
                if (connection != null) connection.close();
            } catch (JMSException e) {
                e.printStackTrace();
            }
        }
    }
}

