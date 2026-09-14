# Flutter-এর Gradle plugin নিজেই io.flutter.** keep rules যোগ করে
# (flutter_proguard_rules.pro)। এখানে শুধু প্রোজেক্ট-নির্দিষ্ট নিয়ম রাখুন।

# Method channel ক্লাসগুলো রিফ্লেকশনে ব্যবহার না হলেও নিরাপদ থাকুক
-keep class io.flutter.plugin.** { *; }

# sqflite / প্লাগইনগুলোর জন্য সাধারণ নিরাপত্তা
-keep class com.tekartik.sqflite.** { *; }