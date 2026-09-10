package com.smartshelfkart.reporting.config;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.firestore.Firestore;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.cloud.FirestoreClient;
import java.io.IOException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.lang.Nullable;

/**
 * The Firestore client, or nothing.
 *
 * <p>Returning a null bean when credentials are absent is intentional. The
 * alternative — failing startup — means the service cannot boot in a test or on
 * a laptop, and the usual workaround for that is a mock so permissive that the
 * authorization path stops being exercised at all. Here, no credentials means
 * {@link com.smartshelfkart.reporting.security.TenantAccess} finds no Firestore
 * and denies every request, which is the correct behaviour for a service that
 * cannot check who is asking.
 */
@Configuration
@ConditionalOnProperty(name = "reporting.offline-mode", havingValue = "false",
        matchIfMissing = true)
public class FirebaseConfig {

    private static final Logger log = LoggerFactory.getLogger(FirebaseConfig.class);

    @Bean
    @Nullable
    public Firestore firestore() {
        try {
            if (FirebaseApp.getApps().isEmpty()) {
                FirebaseApp.initializeApp(FirebaseOptions.builder()
                        .setCredentials(GoogleCredentials.getApplicationDefault())
                        .build());
            }
            return FirestoreClient.getFirestore();
        } catch (IOException | IllegalStateException e) {
            log.warn("No Firebase credentials available; every request will be refused "
                    + "until they are provided. ({})", e.toString());
            return null;
        }
    }
}
