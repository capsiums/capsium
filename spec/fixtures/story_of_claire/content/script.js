document.addEventListener("DOMContentLoaded", function() {
  const markdownContent = document.getElementById('markdown-content').value;
  const tempDiv = document.createElement('div');
  tempDiv.innerHTML = marked.parse(markdownContent);
  const storyElement = document.getElementById('story');
  storyElement.innerHTML = tempDiv.innerHTML;

  // Build TOC from first-level headers (h2)
  const headers = storyElement.querySelectorAll('h2');
  const toc = document.getElementById('toc-list');

  headers.forEach((header, index) => {
    const id = `section-${index}`;
    header.id = id;

    const li = document.createElement('li');
    const a = document.createElement('a');
    a.href = `#${id}`;
    a.textContent = header.textContent;

    li.appendChild(a);
    toc.appendChild(li);
  });

  // Toggle TOC visibility
  const tocToggle = document.getElementById('toc-toggle');
  tocToggle.addEventListener('click', function() {
    document.getElementById('toc').classList.toggle('toc-open');
    document.querySelector('.container').classList.toggle('shifted');
  });

  // Smooth scroll for TOC links
  toc.addEventListener('click', function(event) {
    if (event.target.tagName === 'A') {
      event.preventDefault();
      const targetId = event.target.getAttribute('href').substring(1);
      document.getElementById(targetId).scrollIntoView({
        behavior: 'smooth'
      });
    }
  });

  // Back to top button
  const backToTopButton = document.querySelector('.back-to-top');
  backToTopButton.addEventListener('click', function() {
    window.scrollTo({ top: 0, behavior: 'smooth' });
  });

  // Progress bar
  const progressBar = document.getElementById('progressBar');
  window.addEventListener('scroll', function() {
    const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
    const scrollHeight = document.documentElement.scrollHeight - document.documentElement.clientHeight;
    const progress = (scrollTop / scrollHeight) * 100;
    progressBar.style.width = progress + '%';

    // Show or hide the back-to-top button
    if (scrollTop > 300) {
      backToTopButton.style.display = 'block';
    } else {
      backToTopButton.style.display = 'none';
    }

    // Highlight the current section in the TOC
    const sections = document.querySelectorAll('.story h2');
    const tocLinks = document.querySelectorAll('.toc a');
    let currentSection = sections[0];

    sections.forEach(section => {
      const rect = section.getBoundingClientRect();
      if (rect.top <= 100 && rect.top > -rect.height) {
        currentSection = section;
      }
    });

    tocLinks.forEach(link => {
      link.classList.remove('active');
      if (currentSection && link.getAttribute('href') === `#${currentSection.id}`) {
        link.classList.add('active');
      }
    });
  });
});