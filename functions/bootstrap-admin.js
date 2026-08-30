const admin=require('firebase-admin');
const email=process.argv[2];
if(!email){console.error('Usage: node functions/bootstrap-admin.js admin@example.com');process.exit(1)}
admin.initializeApp();
(async()=>{const u=await admin.auth().getUserByEmail(email);await admin.auth().setCustomUserClaims(u.uid,{...(u.customClaims||{}),admin:true});await admin.firestore().doc(`users/${u.uid}`).set({role:'admin',isActive:true,isBlocked:false},{merge:true});console.log(`Admin enabled: ${email}`)})().catch(e=>{console.error(e);process.exit(1)});
