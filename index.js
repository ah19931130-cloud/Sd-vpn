const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');
admin.initializeApp();

const OPENAI_API_KEY = 'sk-...your-api-key...'; // ⚠️ استخدم مفاتيح البيئة في الإنتاج!

// تحويل الصوت إلى نص عند رفع ملف جديد
exports.transcribeAudio = functions.storage.object().onFinalize(async (object) => {
  const filePath = object.name;
  if (!filePath.startsWith('audios/')) return;

  const bucket = admin.storage().bucket(object.bucket);
  const file = bucket.file(filePath);
  const [url] = await file.getSignedUrl({
    action: 'read',
    expires: Date.now() + 15 * 60 * 1000, // 15 دقيقة
  });

  // إرسال الملف إلى Whisper API
  const formData = new FormData();
  const response = await axios.get(url, { responseType: 'stream' });
  formData.append('file', response.data, { filename: 'audio.m4a' });
  formData.append('model', 'whisper-1');
  formData.append('language', 'ar'); // يمكن إزالتها للكشف التلقائي

  const whisperRes = await axios.post('https://api.openai.com/v1/audio/transcriptions', formData, {
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      ...formData.getHeaders(),
    },
  });

  const transcript = whisperRes.data.text;

  // تخزين النص في Firestore (يبحث عن المستند الذي له نفس رابط الصوت)
  const recordingsRef = admin.firestore().collection('recordings');
  const snapshot = await recordingsRef.where('audioUrl', '==', url).limit(1).get();
  if (!snapshot.empty) {
    await snapshot.docs[0].ref.update({
      transcript,
      status: 'transcribed',
    });
  }
  console.log(`Transcription done for ${filePath}`);
});

// استخراج المهام والمواعيد من النص
exports.extractActions = functions.firestore
  .document('recordings/{docId}')
  .onUpdate(async (change, context) => {
    const after = change.after.data();
    const before = change.before.data();
    // فقط عند تغيير الحالة إلى "transcribed"
    if (after.status !== 'transcribed' || before.status === 'transcribed') return;

    const transcript = after.transcript;
    const today = new Date().toISOString();

    const prompt = `You are an AI assistant that extracts actionable items from Arabic speech transcripts.
Given the transcript, return a JSON object with three arrays: "tasks" (to-do items with a title and optional due date in ISO format), "events" (calendar entries with summary, start, and end if duration is mentioned), and "notes" (general notes).
For dates, convert relative terms like "tomorrow" or "next Monday" to absolute dates based on today's date: ${today}.
If no date is mentioned for a task, set dueDate to null. Output only valid JSON without any markdown formatting.

Transcript: ${transcript}`;

    const gptRes = await axios.post(
      'https://api.openai.com/v1/chat/completions',
      {
        model: 'gpt-4o-mini',
        messages: [{ role: 'user', content: prompt }],
        response_format: { type: 'json_object' },
        temperature: 0,
      },
      {
        headers: {
          Authorization: `Bearer ${OPENAI_API_KEY}`,
          'Content-Type': 'application/json',
        },
      }
    );

    let extracted;
    try {
      extracted = JSON.parse(gptRes.data.choices[0].message.content);
    } catch (e) {
      console.error('Invalid GPT JSON:', e);
      return;
    }

    await change.after.ref.update({
      tasks: extracted.tasks || [],
      events: extracted.events || [],
      notes: extracted.notes || [],
      status: 'extracted',
    });
  });
