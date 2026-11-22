# Switching on iCloud sync

The library, programmes and notes are already shaped for CloudKit and the store asks
for it (`cloudKitDatabase: .automatic`): it syncs as soon as the app carries an iCloud
container. Three steps, the first two by hand:

1. **Create the container** (the App Store Connect API can't): in Xcode, open the
   project, target LargeScore, Signing & Capabilities, add iCloud, tick CloudKit and
   add the container `iCloud.com.kvds.LargeScore`. Or on developer.apple.com:
   Identifiers, iCloud Containers, +.
2. **Run `scripts/enable-icloud.sh`.** It turns on iCloud and Push Notifications for
   the bundle id, adds the container to both entitlements files and the background
   mode sync needs, and makes the App Store profiles (iPad and Mac) again with them.
3. **Deploy the schema once.** A debug build run on a device signed in to iCloud
   creates every record type in CloudKit's development environment at launch
   (`CloudSchema.initializeIfNeeded`, debug builds only, once per install); then
   in the CloudKit Console (icloud.developer.apple.com), container
   `iCloud.com.kvds.LargeScore`, Schema, "Deploy Schema Changes" to Production.
   TestFlight and App Store builds use Production.

The iPad and the Mac then share everything through the private database of the
Apple Account they're signed in to: no sharing to set up.

Done 2026-11-22: steps 1 and 2. The container was registered by a build in Xcode
with Kris's account (Xcode's agent tools build headless and see "No Accounts");
the App Store profiles were made again with it.
