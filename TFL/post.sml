(*  Title:      TFL/post
    ID:         $Id$
    Author:     Konrad Slind, Cambridge University Computer Laboratory
    Copyright   1997  University of Cambridge

Postprocessing of TFL definitions
*)

signature TFL = 
  sig

   val trace : bool ref

   structure Prim : TFL_sig
   val quiet_mode : bool ref
   val message : string -> unit

   val tgoalw : theory -> thm list -> thm list -> thm list
   val tgoal: theory -> thm list -> thm list

   val std_postprocessor : simpset -> theory 
                           -> {induction:thm, rules:thm, TCs:term list list} 
                           -> {induction:thm, rules:thm, nested_tcs:thm list}

   val define_i : theory -> xstring -> term 
                  -> simpset * thm list (*allows special simplication*)
                  -> term list
                  -> theory * {rules:thm list, induct:thm, tcs:term list}

   val define   : theory -> xstring -> string 
                  -> simpset * thm list 
                  -> string list 
                  -> theory * {rules:thm list, induct:thm, tcs:term list}

   val defer_i : theory -> xstring
                  -> thm list (* congruence rules *)
                  -> term list -> theory * thm

   val defer : theory -> xstring
                  -> thm list 
                  -> string list -> theory * thm

   val simplify_defn : simpset * thm list 
                        -> theory * (string * Prim.pattern list)
                        -> {rules:thm list, induct:thm, tcs:term list}

  end;


structure Tfl: TFL =
struct
 structure Prim = Prim
 structure S = USyntax

 (* messages *)

 val quiet_mode = ref false;
 fun message s = if ! quiet_mode then () else writeln s;

 val trace = Prim.trace

 (*---------------------------------------------------------------------------
  * Extract termination goals so that they can be put it into a goalstack, or 
  * have a tactic directly applied to them.
  *--------------------------------------------------------------------------*)
 fun termination_goals rules = 
     map (#1 o Type.freeze_thaw o HOLogic.dest_Trueprop)
       (foldr (fn (th,A) => union_term (prems_of th, A)) (rules, []));

 (*---------------------------------------------------------------------------
  * Finds the termination conditions in (highly massaged) definition and 
  * puts them into a goalstack.
  *--------------------------------------------------------------------------*)
 fun tgoalw thy defs rules = 
   case termination_goals rules of
       [] => error "tgoalw: no termination conditions to prove"
     | L  => goalw_cterm defs 
	       (Thm.cterm_of (Theory.sign_of thy) 
			 (HOLogic.mk_Trueprop(USyntax.list_mk_conj L)));

 fun tgoal thy = tgoalw thy [];

 (*---------------------------------------------------------------------------
 * Three postprocessors are applied to the definition.  It
 * attempts to prove wellfoundedness of the given relation, simplifies the
 * non-proved termination conditions, and finally attempts to prove the 
 * simplified termination conditions.
 *--------------------------------------------------------------------------*)
 fun std_postprocessor ss =
   Prim.postprocess
    {WFtac      = REPEAT (ares_tac [wf_empty, wf_pred_nat, 
				    wf_measure, wf_inv_image, 
				    wf_lex_prod, wf_less_than, wf_trancl] 1),
     terminator = asm_simp_tac ss 1
		  THEN TRY(CLASET' (fn cs => best_tac
			   (cs addSDs [not0_implies_Suc] addss ss)) 1),
     simplifier = Rules.simpl_conv ss []};



 val concl = #2 o Rules.dest_thm;

(*---------------------------------------------------------------------------
 * Postprocess a definition made by "define". This is a separate stage of 
 * processing from the definition stage.
 *---------------------------------------------------------------------------*)
 local 
 structure R = Rules
 structure U = Utils

 (* The rest of these local definitions are for the tricky nested case *)
 val solved = not o U.can S.dest_eq o #2 o S.strip_forall o concl

 fun id_thm th = 
    let val {lhs,rhs} = S.dest_eq(#2(S.strip_forall(#2 (R.dest_thm th))))
    in lhs aconv rhs
    end handle _ => false

 fun prover s = prove_goal HOL.thy s (fn _ => [fast_tac HOL_cs 1]);
 val P_imp_P_iff_True = prover "P --> (P= True)" RS mp;
 val P_imp_P_eq_True = P_imp_P_iff_True RS eq_reflection;
 fun mk_meta_eq r = case concl_of r of
      Const("==",_)$_$_ => r
   |   _ $(Const("op =",_)$_$_) => r RS eq_reflection
   |   _ => r RS P_imp_P_eq_True

 (*Is this the best way to invoke the simplifier??*)
 fun rewrite L = rewrite_rule (map mk_meta_eq (filter(not o id_thm) L))

 fun join_assums th = 
   let val {sign,...} = rep_thm th
       val tych = cterm_of sign
       val {lhs,rhs} = S.dest_eq(#2 (S.strip_forall (concl th)))
       val cntxtl = (#1 o S.strip_imp) lhs  (* cntxtl should = cntxtr *)
       val cntxtr = (#1 o S.strip_imp) rhs  (* but union is solider *)
       val cntxt = gen_union (op aconv) (cntxtl, cntxtr)
   in 
     R.GEN_ALL 
       (R.DISCH_ALL 
	  (rewrite (map (R.ASSUME o tych) cntxt) (R.SPEC_ALL th)))
   end
   val gen_all = S.gen_all
 in
 fun proof_stage ss theory {f, R, rules, full_pats_TCs, TCs} =
   let val dummy = message "Proving induction theorem ..."
       val ind = Prim.mk_induction theory 
                    {fconst=f, R=R, SV=[], pat_TCs_list=full_pats_TCs}
       val dummy = (message "Proved induction theorem."; 
		    message "Postprocessing ...");
       val {rules, induction, nested_tcs} = 
	   std_postprocessor ss theory {rules=rules, induction=ind, TCs=TCs}
   in
   case nested_tcs
   of [] => (message "Postprocessing done.";
	     {induction=induction, rules=rules,tcs=[]})
   | L  => let val dummy = message "Simplifying nested TCs ..."
	       val (solved,simplified,stubborn) =
		U.itlist (fn th => fn (So,Si,St) =>
		      if (id_thm th) then (So, Si, th::St) else
		      if (solved th) then (th::So, Si, St) 
		      else (So, th::Si, St)) nested_tcs ([],[],[])
	       val simplified' = map join_assums simplified
	       val rewr = full_simplify (ss addsimps (solved @ simplified'));
	       val induction' = rewr induction
	       and rules'     = rewr rules
	       val dummy = message "Postprocessing done."
	   in
	   {induction = induction',
		rules = rules',
		  tcs = map (gen_all o S.rhs o #2 o S.strip_forall o concl)
			    (simplified@stubborn)}
	   end
   end;


 (*lcp: curry the predicate of the induction rule*)
 fun curry_rule rl = split_rule_var
			 (head_of (HOLogic.dest_Trueprop (concl_of rl)), 
			  rl);

 (*lcp: put a theorem into Isabelle form, using meta-level connectives*)
 val meta_outer = 
     curry_rule o standard o 
     rule_by_tactic (REPEAT 
		     (FIRSTGOAL (resolve_tac [allI, impI, conjI]
				 ORELSE' etac conjE)));

 (*Strip off the outer !P*)
 val spec'= read_instantiate [("x","P::?'b=>bool")] spec;

 (*this function could be combined with define_i --lcp*)
 fun simplify_defn (ss, tflCongs) (thy,(id,pats)) =
    let val dummy = deny (id mem (Sign.stamp_names_of (Theory.sign_of thy)))
			 ("Recursive definition " ^ id ^ 
			  " would clash with the theory of the same name!")
	val def = freezeT(get_def thy id)   RS   meta_eq_to_obj_eq
	val {theory,rules,TCs,full_pats_TCs,patterns} = 
		 Prim.post_definition (Prim.congs tflCongs)
		    (thy, (def,pats))
	val {lhs=f,rhs} = S.dest_eq(concl def)
	val (_,[R,_]) = S.strip_comb rhs
	val ss' = ss addsimps Prim.default_simps
	val {induction, rules, tcs} = 
	      proof_stage ss' theory 
		{f = f, R = R, rules = rules,
		 full_pats_TCs = full_pats_TCs,
		 TCs = TCs}
	val rules' = map (standard o normalize_thm [RSmp]) (R.CONJUNCTS rules)
    in  {induct = meta_outer
		   (normalize_thm [RSspec,RSmp] (induction RS spec')), 
	 rules = rules', 
	 tcs = (termination_goals rules') @ tcs}
    end
   handle Utils.ERR {mesg,func,module} => 
		error (mesg ^ 
		       "\n    (In TFL function " ^ module ^ "." ^ func ^ ")");

(*---------------------------------------------------------------------------
 * Defining a function with an associated termination relation. 
 *---------------------------------------------------------------------------*)
 fun define_i thy fid R ss_congs eqs = 
   let val {functional,pats} = Prim.mk_functional thy eqs
       val thy = Prim.wfrec_definition0 thy (Sign.base_name fid) R functional
   in (thy, simplify_defn ss_congs (thy, (fid, pats)))
   end;

 fun define thy fid R ss_congs seqs = 
   let val _ =  writeln ("Recursive function " ^ fid)
       val read = readtm (Theory.sign_of thy) (TVar(("DUMMY",0),[])) 
   in  define_i thy fid (read R) ss_congs (map read seqs)  end
   handle Utils.ERR {mesg,...} => error mesg;


(*---------------------------------------------------------------------------
 *
 *     Definitions with synthesized termination relation
 *
 *---------------------------------------------------------------------------*)

 local open USyntax
 in 
 fun func_of_cond_eqn tm =
   #1(strip_comb(#lhs(dest_eq(#2 (strip_forall(#2(strip_imp tm)))))))
 end;

 fun defer_i thy fid congs eqs = 
  let val {rules,R,theory,full_pats_TCs,SV,...} = 
	      Prim.lazyR_def thy (Sign.base_name fid) congs eqs
      val f = func_of_cond_eqn (concl(R.CONJUNCT1 rules handle _ => rules))
      val dummy = (message "Definition made."; 
		   message "Proving induction theorem ...");
      val induction = Prim.mk_induction theory 
                         {fconst=f, R=R, SV=SV, pat_TCs_list=full_pats_TCs}
      val dummy = message "Induction theorem proved."
  in (theory, 
      (*return the conjoined induction rule and recursion equations, 
	with assumptions remaining to discharge*)
      standard (induction RS (rules RS conjI)))
  end

 fun defer thy fid congs seqs = 
   let val read = readtm (Theory.sign_of thy) (TVar(("DUMMY",0),[]))
   in  defer_i thy fid congs (map read seqs)  end
   handle Utils.ERR {mesg,...} => error mesg;
 end;

end;
