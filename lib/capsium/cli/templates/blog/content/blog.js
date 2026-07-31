(function () {
  async function load() {
    try {
      const res = await fetch("/api/v1/data/posts");
      if (!res.ok) throw new Error("HTTP " + res.status);
      const posts = await res.json();
      const sorted = posts.slice().sort((a, b) => (a.date < b.date ? 1 : -1));
      const section = document.getElementById("posts");
      section.innerHTML = sorted.map(function (post) {
        return '<article><h2><a href="/post/' + encodeURIComponent(post.slug) + '">' +
               escapeHtml(post.title) + "</a></h2>" +
               '<p class="meta">' + post.date + "</p>" +
               "<p>" + escapeHtml(post.summary || "") + "</p></article>";
      }).join("");
    } catch (err) {
      document.getElementById("posts").innerHTML = "<p>Failed to load: " + err.message + "</p>";
    }
  }
  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  load();
})();
