pub type App { App(id: String, secret: String) }
pub type Profile { Profile(id: Int, login: String) }
pub type Stats { Stats(stars: Int, forks: Int, issues: Int, language: String) }
pub type Commit { Commit(sha: String, message: String, author: String, date: String) }
