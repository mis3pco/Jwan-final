importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-messaging-compat.js');
const firebaseConfig = {
  apiKey: "AIzaSyDkfYoCX38z7uGjDK-Yu0L_QmUfoSE7SYA",
  authDomain: "jwan-delivery.firebaseapp.com",
  projectId: "jwan-delivery",
  storageBucket: "jwan-delivery.firebasestorage.app",
  messagingSenderId: "1067055041353",
  appId: "1:1067055041353:web:5d466408b59cfb62466898",
  measurementId: "G-GBD6R0GH0Q"
};
if(!firebaseConfig.projectId.startsWith('REPLACE_')){
  firebase.initializeApp(firebaseConfig);
  const messaging=firebase.messaging();
  messaging.onBackgroundMessage(({notification})=>{self.registration.showNotification(notification?.title||'جوان للتوصيل',{body:notification?.body||'لديك تحديث جديد',icon:'/assets/logo.svg'});});
}
