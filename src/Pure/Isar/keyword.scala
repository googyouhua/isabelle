/*  Title:      Pure/Isar/keyword.scala
    Author:     Makarius

Isar keyword classification.
*/

package isabelle


object Keyword
{
  /** keyword classification **/

  /* kinds */

  val DIAG = "diag"
  val DOCUMENT_HEADING = "document_heading"
  val DOCUMENT_BODY = "document_body"
  val DOCUMENT_RAW = "document_raw"
  val THY_BEGIN = "thy_begin"
  val THY_END = "thy_end"
  val THY_DECL = "thy_decl"
  val THY_DECL_BLOCK = "thy_decl_block"
  val THY_LOAD = "thy_load"
  val THY_GOAL = "thy_goal"
  val QED = "qed"
  val QED_SCRIPT = "qed_script"
  val QED_BLOCK = "qed_block"
  val QED_GLOBAL = "qed_global"
  val PRF_GOAL = "prf_goal"
  val PRF_BLOCK = "prf_block"
  val NEXT_BLOCK = "next_block"
  val PRF_OPEN = "prf_open"
  val PRF_CLOSE = "prf_close"
  val PRF_CHAIN = "prf_chain"
  val PRF_DECL = "prf_decl"
  val PRF_ASM = "prf_asm"
  val PRF_ASM_GOAL = "prf_asm_goal"
  val PRF_SCRIPT = "prf_script"
  val PRF_SCRIPT_GOAL = "prf_script_goal"
  val PRF_SCRIPT_ASM_GOAL = "prf_script_asm_goal"
  val QUASI_COMMAND = "quasi_command"


  /* command categories */

  val vacous = Set(DIAG, DOCUMENT_HEADING, DOCUMENT_BODY, DOCUMENT_RAW)

  val diag = Set(DIAG)

  val document_heading = Set(DOCUMENT_HEADING)
  val document_body = Set(DOCUMENT_BODY)
  val document_raw = Set(DOCUMENT_RAW)
  val document = Set(DOCUMENT_HEADING, DOCUMENT_BODY, DOCUMENT_RAW)

  val theory_begin = Set(THY_BEGIN)
  val theory_end = Set(THY_END)

  val theory_load = Set(THY_LOAD)

  val theory = Set(THY_BEGIN, THY_END, THY_LOAD, THY_DECL, THY_DECL_BLOCK, THY_GOAL)

  val theory_block = Set(THY_BEGIN, THY_DECL_BLOCK)

  val theory_body = Set(THY_LOAD, THY_DECL, THY_DECL_BLOCK, THY_GOAL)

  val proof =
    Set(QED, QED_SCRIPT, QED_BLOCK, QED_GLOBAL, PRF_GOAL, PRF_BLOCK, NEXT_BLOCK, PRF_OPEN,
      PRF_CLOSE, PRF_CHAIN, PRF_DECL, PRF_ASM, PRF_ASM_GOAL, PRF_SCRIPT, PRF_SCRIPT_GOAL,
      PRF_SCRIPT_ASM_GOAL)

  val proof_body =
    Set(DIAG, DOCUMENT_HEADING, DOCUMENT_BODY, DOCUMENT_RAW, PRF_BLOCK, NEXT_BLOCK, PRF_OPEN,
      PRF_CLOSE, PRF_CHAIN, PRF_DECL, PRF_ASM, PRF_ASM_GOAL, PRF_SCRIPT, PRF_SCRIPT_GOAL,
      PRF_SCRIPT_ASM_GOAL)

  val theory_goal = Set(THY_GOAL)
  val proof_goal = Set(PRF_GOAL, PRF_ASM_GOAL, PRF_SCRIPT_GOAL, PRF_SCRIPT_ASM_GOAL)
  val qed = Set(QED, QED_SCRIPT, QED_BLOCK)
  val qed_global = Set(QED_GLOBAL)

  val proof_open = proof_goal + PRF_OPEN
  val proof_close = qed + PRF_CLOSE
  val proof_enclose = Set(PRF_BLOCK, NEXT_BLOCK, QED_BLOCK, PRF_CLOSE)



  /** keyword tables **/

  type Spec = ((String, List[String]), List[String])

  val no_spec: Spec = (("", Nil), Nil)
  val quasi_command_spec: Spec = ((QUASI_COMMAND, Nil), Nil)

  object Keywords
  {
    def empty: Keywords = new Keywords()
  }

  class Keywords private(
    val minor: Scan.Lexicon = Scan.Lexicon.empty,
    val major: Scan.Lexicon = Scan.Lexicon.empty,
    protected val quasi_commands: Set[String] = Set.empty,
    protected val commands: Map[String, (String, List[String])] = Map.empty)
  {
    override def toString: String =
    {
      val keywords1 =
        for (name <- minor.iterator.toList) yield {
          if (quasi_commands.contains(name)) (name, quote(name) + " :: \"quasi_command\"")
          else (name, quote(name))
        }
      val keywords2 =
        for ((name, (kind, files)) <- commands.toList) yield {
          (name, quote(name) + " :: " + quote(kind) +
            (if (files.isEmpty) "" else " (" + commas_quote(files) + ")"))
        }
      (keywords1 ::: keywords2).sortBy(_._1).map(_._2).mkString("keywords\n  ", " and\n  ", "")
    }


    /* merge */

    def is_empty: Boolean = minor.is_empty && major.is_empty

    def ++ (other: Keywords): Keywords =
      if (this eq other) this
      else if (is_empty) other
      else {
        val minor1 = minor ++ other.minor
        val major1 = major ++ other.major
        val quasi_commands1 = quasi_commands ++ other.quasi_commands
        val commands1 =
          if (commands eq other.commands) commands
          else if (commands.isEmpty) other.commands
          else (commands /: other.commands) { case (m, e) => if (m.isDefinedAt(e._1)) m else m + e }
        new Keywords(minor1, major1, quasi_commands1, commands1)
      }


    /* add keywords */

    def + (name: String, kind: String = "", tags: List[String] = Nil): Keywords =
      if (kind == "") new Keywords(minor + name, major, quasi_commands, commands)
      else if (kind == QUASI_COMMAND)
        new Keywords(minor + name, major, quasi_commands + name, commands)
      else {
        val major1 = major + name
        val commands1 = commands + (name -> (kind, tags))
        new Keywords(minor, major1, quasi_commands, commands1)
      }

    def add_keywords(header: Thy_Header.Keywords): Keywords =
      (this /: header) {
        case (keywords, (name, ((kind, tags), _), _)) =>
          if (kind == "") keywords + Symbol.decode(name) + Symbol.encode(name)
          else keywords + (Symbol.decode(name), kind, tags) + (Symbol.encode(name), kind, tags)
      }


    /* command kind */

    def command_kind(name: String): Option[String] = commands.get(name).map(_._1)

    def is_command(token: Token, check_kind: String => Boolean): Boolean =
      token.is_command &&
        (command_kind(token.source) match { case Some(k) => check_kind(k) case None => false })

    def is_quasi_command(token: Token): Boolean =
      token.is_keyword && quasi_commands.contains(token.source)


    /* load commands */

    def load_command(name: String): Option[List[String]] =
      commands.get(name) match {
        case Some((THY_LOAD, exts)) => Some(exts)
        case _ => None
      }

    private lazy val load_commands: List[(String, List[String])] =
      (for ((name, (THY_LOAD, files)) <- commands.iterator) yield (name, files)).toList

    def load_commands_in(text: String): Boolean =
      load_commands.exists({ case (cmd, _) => text.containsSlice(cmd) })
  }
}
