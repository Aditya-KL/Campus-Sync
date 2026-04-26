const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");

// Assuming you saved the generated JSON from the previous step into this file
// const curriculumData = require("./curriculum_data.json"); 
// const curriculumData = require("./timetable_data.json"); 
// const curriculumData = require("./freshers_timetable.json"); 
const curriculumData = require("./semcredits_data.json"); 

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function upload() {
  // const collectionName = "curriculum";
  // const collectionName = "timetables"; 
  // const collectionName = "fresher_timetables"; 
  const collectionName = "sem_credits"; 

  for (const docId in curriculumData) {
    try {
      // docId is "CSE_Sem4", "CBT_Sem3", etc.
      // curriculumData[docId] contains the { courses: [...] } map
      await db.collection(collectionName).doc(docId).set(curriculumData[docId]);
      console.log(`✅ Successfully uploaded: ${docId}`);
    } catch (error) {
      console.error(`❌ Error uploading ${docId}:`, error);
    }
  }

  console.log("🎉 All data pushed successfully!");
}

upload();