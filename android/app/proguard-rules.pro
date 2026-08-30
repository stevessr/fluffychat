-keep class com.hiennv.flutter_callkit_incoming.** { *; }

# sqflite_sqlcipher uses JNI class lookups that must keep their Java names in
# minified release builds. Without this, the app can crash while opening the
# encrypted Matrix database during startup.
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }
