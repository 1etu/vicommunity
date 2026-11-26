pub type Attempt { Attempt(id: Int, slug: String, name: String, kind: String, description: String, owner: String, status: String, repo: String, discord: String, mirrors: String, idle: Int, stale: Bool, stars: Int, forks: Int, issues: Int, language: String, recent: Int, gpu: String) }
pub type Entry { Entry(status: String, note: String, age: Int) }
pub type Commit { Commit(sha: String, message: String, author: String, age: Int, diff: String) }
