const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");
const data = require("./database_seed.json");

if (!data.branch) {
  throw new Error("❌ 'branch' key not found in JSON");
}

if (!data.sem_credits) {
  throw new Error("❌ 'sem_credits' key not found in JSON");
}

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function uploadData() {
  try {
    // 🔹 Upload Branch collection
    for (const branchId of Object.keys(data.branch)) {
      const branchDoc = db.collection("branch").doc(branchId);

      await branchDoc.set({ name: branchId });

      const semesters = data.branch[branchId];

      for (const semId of Object.keys(semesters)) {
        await branchDoc
          .collection("semesters")
          .doc(semId)
          .set(semesters[semId]);
      }
    }

    // 🔹 Upload sem_credits collection
    for (const semId of Object.keys(data.sem_credits)) {
      await db.collection("sem_credits")
        .doc(semId)
        .set(data.sem_credits[semId]);
    }

    console.log("🚀 All data uploaded successfully");
  } catch (error) {
    console.error("❌ Error:", error);
  }
}

uploadData();