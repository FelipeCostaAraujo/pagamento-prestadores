package br.com.felipearaujo.diarias

import com.google.firebase.installations.FirebaseInstallations
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "br.com.felipearaujo.diarias/push",
        ).setMethodCallHandler { call, result ->
            if (call.method != "registerInstallation") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            FirebaseMessaging.getInstance().register().addOnCompleteListener { registration ->
                if (!registration.isSuccessful) {
                    result.error(
                        "FCM_REGISTER_FAILED",
                        registration.exception?.message ?: "FCM registration failed",
                        null,
                    )
                    return@addOnCompleteListener
                }

                FirebaseInstallations.getInstance().id.addOnCompleteListener { installation ->
                    if (installation.isSuccessful && !installation.result.isNullOrBlank()) {
                        result.success(installation.result)
                    } else {
                        result.error(
                            "FID_UNAVAILABLE",
                            installation.exception?.message ?: "Firebase installation ID unavailable",
                            null,
                        )
                    }
                }
            }
        }
    }
}
