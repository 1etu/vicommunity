pub type Poll { Poll(id: Int, question: String, login: String, age: Int, closed: Bool, mine: Int, choices: List(Choice)) }
pub type Choice { Choice(id: Int, label: String, votes: Int) }
