// Scoring handler. Reads the questions dataset from inside the same
// package, compares each answer, returns {score, total, message}.
export default async function handle(request) {
  if (request.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }
  const payload = await request.json();
  const answers = payload.answers || {};
  const res = await fetch("/api/v1/data/questions");
  const questions = await res.json();
  let score = 0;
  for (const q of questions) {
    if (answers[q.id] === q.answer) score += 1;
  }
  return new Response(
    JSON.stringify({
      score,
      total: questions.length,
      message: score === questions.length ? "Perfect!" : "Keep practicing.",
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
}
