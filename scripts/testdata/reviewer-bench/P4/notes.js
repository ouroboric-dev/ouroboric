// The notes of every person, kept in memory. A note id is unique across all people.
const all = new Map(); // id -> {id, owner, text}, oldest first
let nextId = 1;

// of returns the notes of one person: the server reaches notes only through it.
function of(owner) {
  return {
    // list returns the person's notes, newest first.
    list() {
      return [...all.values()].filter(n => n.owner === owner).reverse().map(n => ({id: n.id, text: n.text}));
    },
    add(text) {
      const n = {id: nextId++, owner, text};
      all.set(n.id, n);
      return {id: n.id, text: n.text};
    },
    // remove deletes a note and says whether it was there.
    remove(id) {
      return all.delete(id);
    },
  };
}

module.exports = {of};
