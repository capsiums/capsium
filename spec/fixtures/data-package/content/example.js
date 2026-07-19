function fetchAnimals() {
  return fetch('/api/v1/data/animals')
    .then(response => response.json())
    .then(data => data)
    .catch(error => console.error('Error fetching animals:', error));
}

function displayAnimals(animals) {
  const animalList = document.getElementById('animalList');
  animalList.innerHTML = '';
  animals.forEach(animal => {
    const li = document.createElement('li');
    li.textContent = `${animal.name} (${animal.type}) - ${animal.habitat}`;
    li.addEventListener('click', () => displayAnimalDetails(animal));
    animalList.appendChild(li);
  });
}

function displayAnimalDetails(animal) {
  const animalDetails = document.getElementById('animalDetails');
  animalDetails.innerHTML = `<h3>${animal.name}</h3>
    <p>Type: ${animal.type}</p>
    <p>Habitat: ${animal.habitat}</p>
    <p>Diet: ${animal.diet}</p>
    <p>Lifespan: ${animal.lifespan}</p>
    <p>Conservation Status: ${animal.conservation_status}</p>
    <p>Category ID: ${animal.category_id}</p>`;
}

function filterAnimalsByCategory(animals, categoryId) {
  return animals.filter(animal => animal.category_id === categoryId);
}

document.getElementById('loadAnimals').addEventListener('click', () => {
  fetchAnimals().then(data => displayAnimals(data.animals));
});

document.getElementById('search').addEventListener('input', (event) => {
  const searchTerm = event.target.value.toLowerCase();
  fetchAnimals().then(data => {
    const filteredAnimals = data.animals.filter(animal => animal.name.toLowerCase().includes(searchTerm));
    displayAnimals(filteredAnimals);
  });
});

document.getElementById('categoryFilter').addEventListener('change', (event) => {
  const categoryId = parseInt(event.target.value, 10);
  fetchAnimals().then(data => {
    const filteredAnimals = filterAnimalsByCategory(data.animals, categoryId);
    displayAnimals(filteredAnimals);
  });
});