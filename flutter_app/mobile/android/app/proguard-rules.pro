# Keep Google Tink crypto library classes
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn com.google.api.client.**
-dontwarn org.joda.time.**
-keep class com.google.crypto.tink.** { *; }
-keep class com.google.errorprone.annotations.** { *; }
-keep class javax.annotation.** { *; }
-keep class javax.annotation.concurrent.** { *; }
-keep class com.google.api.client.** { *; }
-keep class org.joda.time.** { *; }

# Keep flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }
