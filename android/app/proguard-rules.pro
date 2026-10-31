# Release builds shrink the code, and the shrinker cannot see classes that are
# only created by reflection. Room (used by WorkManager, which ML Kit pulls in)
# creates its generated *_Impl databases that way, so without this the release
# app crashed on launch: "Failed to create an instance of
# androidx.work.impl.WorkDatabase".
-keep class * extends androidx.room.RoomDatabase { <init>(); }
