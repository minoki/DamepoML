(*
 * Copyright (c) 2021 ARATA Mizuki
 * This file is part of LunarML.
 *)
structure USyntax = struct
datatype VId = MkVId of string * int
datatype TyVar = NamedTyVar of string * bool * int
               | AnonymousTyVar of int
datatype TyName = MkTyName of string * int
datatype StrId = MkStrId of string * int
datatype LongVId = MkShortVId of VId
                 | MkLongVId of StrId * Syntax.StrId list * Syntax.VId
datatype LongStrId = MkLongStrId of StrId * Syntax.StrId list
fun eqUTyVar(NamedTyVar(name,eq,a),NamedTyVar(name',eq',b)) = name = name' andalso eq = eq' andalso a = b
  | eqUTyVar(AnonymousTyVar a, AnonymousTyVar b) = a = b
  | eqUTyVar(_, _) = false
fun eqTyName(MkTyName(_,a),MkTyName(_,b)) = a = b
fun eqVId(a, b : VId) = a = b
fun eqULongVId(MkShortVId a, MkShortVId b) = eqVId(a, b)
  | eqULongVId(MkLongVId(s, t, u), MkLongVId(s', t', u')) = s = s' andalso t = t' andalso u = u'
  | eqULongVId(_, _) = false

structure TyVarKey = struct
type ord_key = TyVar
fun compare(NamedTyVar(x,_,a), NamedTyVar(y,_,b)) = (case String.compare (x,y) of
                                                         EQUAL => Int.compare(a,b)
                                                       | ord => ord
                                                    )
  | compare(AnonymousTyVar(a), AnonymousTyVar(b)) = Int.compare(a,b)
  | compare(NamedTyVar _, AnonymousTyVar _) = LESS
  | compare(AnonymousTyVar _, NamedTyVar _) = GREATER
end : ORD_KEY
structure TyVarSet = RedBlackSetFn(TyVarKey)
structure TyVarMap = RedBlackMapFn(TyVarKey)

datatype Ty = TyVar of SourcePos.span * TyVar (* type variable *)
            | RecordType of SourcePos.span * (Syntax.Label * Ty) list (* record type expression *)
            | TyCon of SourcePos.span * Ty list * TyName (* type construction *)
            | FnType of SourcePos.span * Ty * Ty (* function type expression *)

fun PairType(span, a, b) = RecordType(span, [(Syntax.NumericLabel 1, a), (Syntax.NumericLabel 2, b)])
fun TupleType(span, xs) = let fun doFields i nil = nil
                                | doFields i (x :: xs) = (Syntax.NumericLabel i, x) :: doFields (i + 1) xs
                          in RecordType (span, doFields 1 xs)
                          end

structure VIdKey = struct
type ord_key = VId
fun compare(MkVId(x,a), MkVId(y,b)) = case String.compare (x,y) of
                                          EQUAL => Int.compare(a,b)
                                        | ord => ord
end : ORD_KEY
structure VIdSet = RedBlackSetFn(VIdKey)
structure VIdMap = RedBlackMapFn(VIdKey)

structure TyNameKey = struct
type ord_key = TyName
fun compare(MkTyName(x,a), MkTyName(y,b)) = case String.compare (x,y) of
                                                EQUAL => Int.compare(a,b)
                                              | ord => ord
end : ORD_KEY
structure TyNameSet = RedBlackSetFn(TyNameKey)
structure TyNameMap = RedBlackMapFn(TyNameKey)

structure StrIdKey = struct
type ord_key = StrId
fun compare(MkStrId(x,a), MkStrId(y,b)) = case String.compare (x,y) of
                                              EQUAL => Int.compare(a,b)
                                            | ord => ord
end : ORD_KEY
structure StrIdSet = RedBlackSetFn(StrIdKey)
structure StrIdMap = RedBlackMapFn(StrIdKey)

structure LongVIdKey = struct
type ord_key = LongVId
fun compare(MkShortVId(vid), MkShortVId(vid')) = VIdKey.compare(vid, vid')
  | compare(MkShortVId _, MkLongVId _) = LESS
  | compare(MkLongVId _, MkShortVId _) = GREATER
  | compare(MkLongVId(strid0, strids, vid), MkLongVId(strid0', strids', vid')) = case StrIdKey.compare(strid0, strid0') of
                                                                                     EQUAL => (case Syntax.VIdKey.compare(vid, vid') of
                                                                                                  EQUAL => List.collate Syntax.StrIdKey.compare (strids, strids')
                                                                                                | x => x
                                                                                              )
                                                                                   | x => x
end : ORD_KEY
structure LongVIdSet = RedBlackSetFn(LongVIdKey)
structure LongVIdMap = RedBlackMapFn(LongVIdKey)

datatype UnaryConstraint
  = HasField of { sourceSpan : SourcePos.span
                , label : Syntax.Label
                , fieldTy : Ty
                }
  | IsEqType of SourcePos.span
  | IsIntegral of SourcePos.span (* Int, Word; div, mod; defaults to int *)
  | IsSignedReal of SourcePos.span (* Int, Real; abs; defaults to int *)
  | IsRing of SourcePos.span (* Int, Word, Real; *, +, -, ~; defaults to int *)
  | IsField of SourcePos.span (* Real; /; defaults to real *)
  | IsSigned of SourcePos.span (* Int, Real; defaults to int *)
  | IsOrdered of SourcePos.span (* NumTxt; <, >, <=, >=; defaults to int *)

datatype Constraint
  = EqConstr of SourcePos.span * Ty * Ty (* ty1 = ty2 *)
  | UnaryConstraint of SourcePos.span * Ty * UnaryConstraint

datatype TypeFunction = TypeFunction of TyVar list * Ty
datatype TypeScheme = TypeScheme of (TyVar * UnaryConstraint list) list * Ty
type ValEnv = (TypeScheme * Syntax.IdStatus) Syntax.VIdMap.map
val emptyValEnv : ValEnv = Syntax.VIdMap.empty

type TypeStructure = { typeFunction : TypeFunction
                     , valEnv : ValEnv
                     }

datatype Signature' = MkSignature of Signature
withtype Signature = { valMap : (TypeScheme * Syntax.IdStatus) Syntax.VIdMap.map
                     , tyConMap : TypeStructure Syntax.TyConMap.map
                     , strMap : Signature' Syntax.StrIdMap.map
                     }
type QSignature = { s : Signature
                  , bound : { arity : int, admitsEquality : bool, longtycon : Syntax.LongTyCon } TyNameMap.map
                  }

datatype Pat = WildcardPat of SourcePos.span
             | SConPat of SourcePos.span * Syntax.SCon (* special constant *)
             | VarPat of SourcePos.span * VId * Ty (* variable *)
             | RecordPat of { sourceSpan : SourcePos.span, fields : (Syntax.Label * Pat) list, wildcard : bool }
             | ConPat of { sourceSpan : SourcePos.span, longvid : LongVId, payload : Pat option, tyargs : Ty list, isSoleConstructor : bool }
             | TypedPat of SourcePos.span * Pat * Ty (* typed *)
             | LayeredPat of SourcePos.span * VId * Ty * Pat (* layered *)

datatype TypBind = TypBind of SourcePos.span * TyVar list * Syntax.TyCon * Ty
datatype ConBind = ConBind of SourcePos.span * VId * Ty option
datatype DatBind = DatBind of SourcePos.span * TyVar list * TyName * ConBind list * (* admits equality? *) bool
datatype ExBind = ExBind of SourcePos.span * VId * Ty option (* <op> vid <of ty> *)
                | ExReplication of SourcePos.span * VId * LongVId * Ty option

datatype Exp = SConExp of SourcePos.span * Syntax.SCon (* special constant *)
             | VarExp of SourcePos.span * LongVId * Syntax.IdStatus * (Ty * UnaryConstraint list) list (* identifiers with type arguments *)
             | RecordExp of SourcePos.span * (Syntax.Label * Exp) list (* record *)
             | LetInExp of SourcePos.span * Dec list * Exp (* local declaration *)
             | AppExp of SourcePos.span * Exp * Exp (* function, argument *)
             | TypedExp of SourcePos.span * Exp * Ty
             | HandleExp of SourcePos.span * Exp * (Pat * Exp) list
             | RaiseExp of SourcePos.span * Exp
             | IfThenElseExp of SourcePos.span * Exp * Exp * Exp
             | CaseExp of SourcePos.span * Exp * Ty * (Pat * Exp) list
             | FnExp of SourcePos.span * VId * Ty * Exp (* parameter name, parameter type, body *)
             | ProjectionExp of { sourceSpan : SourcePos.span, label : Syntax.Label, recordTy : Ty, fieldTy : Ty }
             | ListExp of SourcePos.span * Exp vector * Ty
     and Dec = ValDec of SourcePos.span * ValBind list (* non-recursive *)
             | RecValDec of SourcePos.span * ValBind list (* recursive (val rec) *)
             | TypeDec of SourcePos.span * TypBind list (* not used by the type checker *)
             | DatatypeDec of SourcePos.span * DatBind list
             | ExceptionDec of SourcePos.span * ExBind list
             | GroupDec of SourcePos.span * Dec list
     and ValBind = TupleBind of SourcePos.span * (VId * Ty) list * Exp (* monomorphic binding; produced during type-check *)
                 | PolyVarBind of SourcePos.span * VId * TypeScheme * Exp (* polymorphic binding; produced during type-check *)

datatype StrExp = StructExp of { sourceSpan : SourcePos.span
                               , valMap : (LongVId * Syntax.IdStatus) Syntax.VIdMap.map
                               , tyConMap : TypeStructure Syntax.TyConMap.map
                               , strMap : LongStrId Syntax.StrIdMap.map
                               }
                | StrIdExp of SourcePos.span * LongStrId
                (* TODO: functor application *)
                | LetInStrExp of SourcePos.span * StrDec list * StrExp
     and StrDec = CoreDec of SourcePos.span * Dec
                | StrBindDec of SourcePos.span * StrId * StrExp * Signature
                | GroupStrDec of SourcePos.span * StrDec list

datatype TopDec = StrDec of StrDec
                (* | SigDec of Syntax.SigId * SigExp *)
type Program = (TopDec list) list

local
    fun doFields i nil = nil
      | doFields i (x :: xs) = (Syntax.NumericLabel i, x) :: doFields (i + 1) xs
in 
fun TuplePat(span, xs) = RecordPat { sourceSpan = span, fields = doFields 1 xs, wildcard = false }
fun TupleExp(span, xs) = RecordExp (span, doFields 1 xs)
end

fun getSourceSpanOfTy(TyVar(span, _)) = span
  | getSourceSpanOfTy(RecordType(span, _)) = span
  | getSourceSpanOfTy(TyCon(span, _, _)) = span
  | getSourceSpanOfTy(FnType(span, _, _)) = span

fun getSourceSpanOfExp(SConExp(span, _)) = span
  | getSourceSpanOfExp(VarExp(span, _, _, _)) = span
  | getSourceSpanOfExp(RecordExp(span, _)) = span
  | getSourceSpanOfExp(LetInExp(span, _, _)) = span
  | getSourceSpanOfExp(AppExp(span, _, _)) = span
  | getSourceSpanOfExp(TypedExp(span, _, _)) = span
  | getSourceSpanOfExp(HandleExp(span, _, _)) = span
  | getSourceSpanOfExp(RaiseExp(span, _)) = span
  | getSourceSpanOfExp(IfThenElseExp(span, _, _, _)) = span
  | getSourceSpanOfExp(CaseExp(span, _, _, _)) = span
  | getSourceSpanOfExp(FnExp(span, _, _, _)) = span
  | getSourceSpanOfExp(ProjectionExp{sourceSpan, ...}) = sourceSpan
  | getSourceSpanOfExp(ListExp(span, _, _)) = span

(* pretty printing *)
structure PrettyPrint = struct
fun print_VId(MkVId(name, n)) = "MkVId(\"" ^ String.toString name ^ "\"," ^ Int.toString n ^ ")"
fun print_LongVId(MkShortVId(vid)) = print_VId vid
  | print_LongVId(MkLongVId(MkStrId(strid, n), strids, vid)) = "MkLongVId(" ^ strid ^ "@" ^ Int.toString n ^ "," ^ Syntax.print_list Syntax.print_StrId strids ^ "," ^ Syntax.print_VId vid ^ ")"
fun print_TyVar(NamedTyVar(tvname, eq, n)) = "NamedTyVar(\"" ^ String.toString tvname ^ "\"," ^ Bool.toString eq ^ "," ^ Int.toString n ^ ")"
  | print_TyVar(AnonymousTyVar(n)) = "AnonymousTyVar(" ^ Int.toString n ^ ")"
fun print_TyName (MkTyName ("int", 0)) = "primTyName_int"
  | print_TyName (MkTyName ("word", 1)) = "primTyName_word"
  | print_TyName (MkTyName ("real", 2)) = "primTyName_real"
  | print_TyName (MkTyName ("string", 3)) = "primTyName_string"
  | print_TyName (MkTyName ("char", 4)) = "primTyName_char"
  | print_TyName (MkTyName ("exn", 5)) = "primTyName_exn"
  | print_TyName (MkTyName ("bool", 6)) = "primTyName_bool"
  | print_TyName (MkTyName ("ref", 7)) = "primTyName_ref"
  | print_TyName (MkTyName ("list", 8)) = "primTyName_list"
  | print_TyName (MkTyName(tyconname, n)) = "MkTyName(\"" ^ String.toString tyconname ^ "\"," ^ Int.toString n ^ ")"
fun print_Ty (TyVar(_,x)) = "TyVar(" ^ print_TyVar x ^ ")"
  | print_Ty (RecordType(_,xs)) = (case Syntax.extractTuple (1, xs) of
                                       NONE => "RecordType " ^ Syntax.print_list (Syntax.print_pair (Syntax.print_Label,print_Ty)) xs
                                     | SOME ys => "TupleType " ^ Syntax.print_list print_Ty ys
                                  )
  | print_Ty (TyCon(_,[],MkTyName("int", 0))) = "primTy_int"
  | print_Ty (TyCon(_,[],MkTyName("word", 1))) = "primTy_word"
  | print_Ty (TyCon(_,[],MkTyName("real", 2))) = "primTy_real"
  | print_Ty (TyCon(_,[],MkTyName("string", 3))) = "primTy_string"
  | print_Ty (TyCon(_,[],MkTyName("char", 4))) = "primTy_char"
  | print_Ty (TyCon(_,[],MkTyName("exn", 5))) = "primTy_exn"
  | print_Ty (TyCon(_,[],MkTyName("bool", 6))) = "primTy_bool"
  | print_Ty (TyCon(_,x,y)) = "TyCon(" ^ Syntax.print_list print_Ty x ^ "," ^ print_TyName y ^ ")"
  | print_Ty (FnType(_,x,y)) = "FnType(" ^ print_Ty x ^ "," ^ print_Ty y ^ ")"
fun print_Pat (WildcardPat _) = "WildcardPat"
  | print_Pat (SConPat(_, x)) = "SConPat(" ^ Syntax.print_SCon x ^ ")"
  | print_Pat (VarPat(_, vid, ty)) = "VarPat(" ^ print_VId vid ^ "," ^ print_Ty ty ^ ")"
  | print_Pat (TypedPat (_, pat, ty)) = "TypedPat(" ^ print_Pat pat ^ "," ^ print_Ty ty ^ ")"
  | print_Pat (LayeredPat (_, vid, ty, pat)) = "TypedPat(" ^ print_VId vid ^ "," ^ print_Ty ty ^ "," ^ print_Pat pat ^ ")"
  | print_Pat (ConPat { longvid, payload, tyargs, ...}) = "ConPat(" ^ print_LongVId longvid ^ "," ^ Syntax.print_option print_Pat payload ^ "," ^ Syntax.print_list print_Ty tyargs ^ ")"
  | print_Pat (RecordPat{fields = x, wildcard = false, ...}) = (case Syntax.extractTuple (1, x) of
                                                               NONE => "RecordPat(" ^ Syntax.print_list (Syntax.print_pair (Syntax.print_Label, print_Pat)) x ^ ",false)"
                                                             | SOME ys => "TuplePat " ^ Syntax.print_list print_Pat ys
                                                          )
  | print_Pat (RecordPat{fields = x, wildcard = true, ...}) = "RecordPat(" ^ Syntax.print_list (Syntax.print_pair (Syntax.print_Label, print_Pat)) x ^ ",true)"
(* | print_Pat _ = "<Pat>" *)
fun print_Exp (SConExp(_, x)) = "SConExp(" ^ Syntax.print_SCon x ^ ")"
  | print_Exp (VarExp(_, x, idstatus, tyargs)) = "VarExp(" ^ print_LongVId x ^ "," ^ Syntax.print_IdStatus idstatus ^ "," ^ Syntax.print_list (Syntax.print_pair (print_Ty, Syntax.print_list print_UnaryConstraint)) tyargs ^ ")"
  | print_Exp (RecordExp(_, x)) = (case Syntax.extractTuple (1, x) of
                                       NONE => "RecordExp " ^ Syntax.print_list (Syntax.print_pair (Syntax.print_Label, print_Exp)) x
                                     | SOME ys => "TupleExp " ^ Syntax.print_list print_Exp ys
                                  )
  | print_Exp (LetInExp(_,decls,x)) = "LetInExp(" ^ Syntax.print_list print_Dec decls ^ "," ^ print_Exp x ^ ")"
  | print_Exp (AppExp(_,x,y)) = "AppExp(" ^ print_Exp x ^ "," ^ print_Exp y ^ ")"
  | print_Exp (TypedExp(_,x,y)) = "TypedExp(" ^ print_Exp x ^ "," ^ print_Ty y ^ ")"
  | print_Exp (HandleExp(_,x,y)) = "HandleExp(" ^ print_Exp x ^ "," ^ Syntax.print_list (Syntax.print_pair (print_Pat, print_Exp)) y ^ ")"
  | print_Exp (RaiseExp(_,x)) = "RaiseExp(" ^ print_Exp x ^ ")"
  | print_Exp (IfThenElseExp(_,x,y,z)) = "IfThenElseExp(" ^ print_Exp x ^ "," ^ print_Exp y ^ "," ^ print_Exp z ^ ")"
  | print_Exp (CaseExp(_,x,ty,y)) = "CaseExp(" ^ print_Exp x ^ "," ^ print_Ty ty ^ "," ^ Syntax.print_list (Syntax.print_pair (print_Pat,print_Exp)) y ^ ")"
  | print_Exp (FnExp(_,pname,pty,body)) = "FnExp(" ^ print_VId pname ^ "," ^ print_Ty pty ^ "," ^ print_Exp body ^ ")"
  | print_Exp (ProjectionExp { label = label, recordTy = recordTy, fieldTy = fieldTy, ... }) = "ProjectionExp{label=" ^ Syntax.print_Label label ^ ",recordTy=" ^ print_Ty recordTy ^ ",fieldTy=" ^ print_Ty fieldTy ^ "}"
  | print_Exp (ListExp _) = "ListExp"
and print_Dec (ValDec(_,valbinds)) = "ValDec'(" ^ Syntax.print_list print_ValBind valbinds ^ ")"
  | print_Dec (RecValDec(_,valbinds)) = "RecValDec'(" ^ Syntax.print_list print_ValBind valbinds ^ ")"
  | print_Dec (TypeDec(_, typbinds)) = "TypeDec(" ^ Syntax.print_list print_TypBind typbinds ^ ")"
  | print_Dec (DatatypeDec(_, datbinds)) = "DatatypeDec(" ^ Syntax.print_list print_DatBind datbinds ^ ")"
  | print_Dec (ExceptionDec(_, exbinds)) = "ExceptionDec"
  | print_Dec (GroupDec _) = "GroupDec"
and print_TypBind (TypBind(_, tyvars, tycon, ty)) = "TypBind(" ^ Syntax.print_list print_TyVar tyvars ^ "," ^ Syntax.print_TyCon tycon ^ "," ^ print_Ty ty ^ ")"
and print_DatBind (DatBind(_, tyvars, tycon, conbinds, _)) = "DatBind(" ^ Syntax.print_list print_TyVar tyvars ^ "," ^ print_TyName tycon ^ "," ^ Syntax.print_list print_ConBind conbinds ^ ")"
and print_ConBind (ConBind(_, vid, NONE)) = "ConBind(" ^ print_VId vid ^ ",NONE)"
  | print_ConBind (ConBind(_, vid, SOME ty)) = "ConBind(" ^ print_VId vid ^ ",SOME " ^ print_Ty ty ^ ")"
and print_ValBind (TupleBind (_, xs, exp)) = "TupleBind(" ^ Syntax.print_list (Syntax.print_pair (print_VId, print_Ty)) xs ^ "," ^ print_Exp exp ^ ")"
  | print_ValBind (PolyVarBind (_, name, tysc, exp)) = "PolyVarBind(" ^ print_VId name ^ "," ^ print_TypeScheme tysc ^ "," ^ print_Exp exp ^ ")"
and print_TyVarMap print_elem x = Syntax.print_list (Syntax.print_pair (print_TyVar,print_elem)) (TyVarMap.foldri (fn (k,x,ys) => (k,x) :: ys) [] x)
and print_VIdMap print_elem x = Syntax.print_list (Syntax.print_pair (print_VId,print_elem)) (VIdMap.foldri (fn (k,x,ys) => (k,x) :: ys) [] x)
and print_UnaryConstraint (HasField { sourceSpan, label, fieldTy }) = "HasField{label=" ^ Syntax.print_Label label ^ ",fieldTy=" ^ print_Ty fieldTy ^ "}"
  | print_UnaryConstraint (IsEqType _) = "IsEqType"
  | print_UnaryConstraint (IsIntegral _) = "IsIntegral"
  | print_UnaryConstraint (IsSignedReal _) = "IsSignedReal"
  | print_UnaryConstraint (IsRing _) = "IsRing"
  | print_UnaryConstraint (IsField _) = "IsField"
  | print_UnaryConstraint (IsSigned _) = "IsSigned"
  | print_UnaryConstraint (IsOrdered _) = "IsOrdered"
and print_TypeScheme (TypeScheme(tyvars, ty)) = "TypeScheme(" ^ Syntax.print_list (Syntax.print_pair (print_TyVar, Syntax.print_list print_UnaryConstraint)) tyvars ^ "," ^ print_Ty ty ^ ")"
and print_ValEnv env = print_VIdMap (Syntax.print_pair (print_TypeScheme,Syntax.print_IdStatus)) env
fun print_TyVarSet x = Syntax.print_list print_TyVar (TyVarSet.foldr (fn (x,ys) => x :: ys) [] x)
fun print_TyNameMap print_elem x = Syntax.print_list (Syntax.print_pair (print_TyName,print_elem)) (TyNameMap.foldri (fn (k,x,ys) => (k,x) :: ys) [] x)
val print_Decs = Syntax.print_list print_Dec
fun print_Constraint(EqConstr(span,ty1,ty2)) = "EqConstr(" ^ print_Ty ty1 ^ "," ^ print_Ty ty2 ^ ")"
  | print_Constraint(UnaryConstraint(span,ty,ct)) = "Unary(" ^ print_Ty ty ^ "," ^ print_UnaryConstraint ct ^ ")"
end (* structure PrettyPrint *)
open PrettyPrint

(* freeTyVarsInTy : TyVarSet * Ty -> TyVarSet *)
fun freeTyVarsInTy(bound, ty)
    = (case ty of
           TyVar(_,tv) => if TyVarSet.member(bound, tv) then
                              TyVarSet.empty
                          else
                              TyVarSet.singleton tv
         | RecordType(_,xs) => List.foldl (fn ((_, ty), set) => TyVarSet.union(freeTyVarsInTy(bound, ty), set)) TyVarSet.empty xs
         | TyCon(_,xs,_) => List.foldl (fn (ty, set) => TyVarSet.union(freeTyVarsInTy(bound, ty), set)) TyVarSet.empty xs
         | FnType(_,s,t) => TyVarSet.union(freeTyVarsInTy(bound, s), freeTyVarsInTy(bound, t))
      )

(* applySubstTy : Ty TyVarMap.map -> Ty -> Ty *)
fun applySubstTy subst
    = let fun substTy (ty as TyVar(_, tv'))
              = (case TyVarMap.find(subst, tv') of
                     NONE => ty
                   | SOME replacement => replacement
                )
            | substTy (RecordType(span, fields)) = RecordType (span, Syntax.mapRecordRow substTy fields)
            | substTy (TyCon(span, tyargs, tycon)) = TyCon(span, List.map substTy tyargs, tycon)
            | substTy (FnType(span, ty1, ty2)) = FnType(span, substTy ty1, substTy ty2)
      in substTy
      end

(* mapTy : Context * Ty TyVarMap.map * bool -> { doExp : Exp -> Exp, doDec : Dec -> Dec, doDecs : Dec list -> Dec list, ... } *)
fun mapTy (ctx : { nextTyVar : int ref, nextVId : 'a, tyVarConstraints : 'c, tyVarSubst : 'd }, subst, avoidCollision)
    = let val doTy = applySubstTy subst
          val range = TyVarMap.foldl (fn (ty, tyvarset) => TyVarSet.union(freeTyVarsInTy(TyVarSet.empty, ty), tyvarset)) TyVarSet.empty subst
          fun genFreshTyVars(subst, tyvars) = List.foldr (fn (tv, (subst, tyvars)) => if avoidCollision andalso TyVarSet.member (range, tv) then
                                                                                          let val nextTyVar = #nextTyVar ctx
                                                                                              val x = !nextTyVar
                                                                                              val () = nextTyVar := x + 1
                                                                                              val tv' = case tv of
                                                                                                            NamedTyVar(name, eq, _) => NamedTyVar(name, eq, x)
                                                                                                          | AnonymousTyVar _ => AnonymousTyVar x
                                                                                          in (TyVarMap.insert (subst, tv, TyVar(SourcePos.nullSpan, tv')), tv' :: tyvars)
                                                                                        end
                                                                                      else
                                                                                          (subst, tv :: tyvars))
                                                         (subst, []) tyvars
          fun doUnaryConstraint(HasField{sourceSpan, label, fieldTy}) = HasField{sourceSpan=sourceSpan, label=label, fieldTy=doTy fieldTy}
            | doUnaryConstraint ct = ct
          fun doTypeScheme(TypeScheme (tyvarsWithConstraints, ty)) = let val (subst, tyvars) = genFreshTyVars(subst, List.map #1 tyvarsWithConstraints)
                                                                         val constraints = List.map (fn (_, cts) => List.map doUnaryConstraint cts) tyvarsWithConstraints
                                                                     in TypeScheme (ListPair.zip (tyvars, constraints), applySubstTy subst ty)
                                                                     end
          val doValEnv = VIdMap.map (fn (tysc, idstatus) => (doTypeScheme tysc, idstatus))
          fun doExp(e as SConExp _) = e
            | doExp(VarExp(span, longvid, idstatus, tyargs)) = VarExp(span, longvid, idstatus, List.map (fn (ty, cts) => (doTy ty, List.map doUnaryConstraint cts)) tyargs)
            | doExp(RecordExp(span, fields)) = RecordExp(span, Syntax.mapRecordRow doExp fields)
            | doExp(LetInExp(span, decls, e)) = LetInExp(span, List.map doDec decls, doExp e)
            | doExp(AppExp(span, e1, e2)) = AppExp(span, doExp e1, doExp e2)
            | doExp(TypedExp(span, e, ty)) = TypedExp(span, doExp e, doTy ty)
            | doExp(HandleExp(span, e, matches)) = HandleExp(span, doExp e, List.map doMatch matches)
            | doExp(RaiseExp(span, e)) = RaiseExp(span, doExp e)
            | doExp(IfThenElseExp(span, e1, e2, e3)) = IfThenElseExp(span, doExp e1, doExp e2, doExp e3)
            | doExp(CaseExp(span, e, ty, matches)) = CaseExp(span, doExp e, doTy ty, List.map doMatch matches)
            | doExp(FnExp(span, vid, ty, body)) = FnExp(span, vid, doTy ty, doExp body)
            | doExp(ProjectionExp { sourceSpan, label, recordTy, fieldTy }) = ProjectionExp { sourceSpan = sourceSpan, label = label, recordTy = doTy recordTy, fieldTy = doTy fieldTy }
            | doExp(ListExp(span, xs, ty)) = ListExp(span, Vector.map doExp xs, doTy ty)
          and doDec(ValDec(span, valbind)) = ValDec(span, List.map doValBind valbind)
            | doDec(RecValDec(span, valbind)) = RecValDec(span, List.map doValBind valbind)
            | doDec(TypeDec(span, typbinds)) = TypeDec(span, List.map doTypBind typbinds)
            | doDec(DatatypeDec(span, datbinds)) = DatatypeDec(span, List.map doDatBind datbinds)
            | doDec(ExceptionDec(span, exbinds)) = ExceptionDec(span, List.map doExBind exbinds)
            | doDec(GroupDec(span, decs)) = GroupDec(span, List.map doDec decs)
          and doValBind(TupleBind(span, xs, exp)) = TupleBind(span, List.map (fn (vid, ty) => (vid, doTy ty)) xs, doExp exp)
            | doValBind(PolyVarBind(span, vid, tysc as TypeScheme (tyvarsWithConstraints, ty), exp)) = let val (subst, tyvars) = genFreshTyVars(subst, List.map #1 tyvarsWithConstraints)
                                                                                                           val constraints = List.map (fn (_, cts) => List.map doUnaryConstraint cts) tyvarsWithConstraints
                                                                                                       in PolyVarBind(span, vid, TypeScheme (ListPair.zip (tyvars, constraints), applySubstTy subst ty), #doExp (mapTy (ctx, subst, avoidCollision)) exp)
                                                                                                       end
          and doMatch(pat, exp) = (doPat pat, doExp exp)
          and doPat(pat as WildcardPat _) = pat
            | doPat(s as SConPat _) = s
            | doPat(VarPat(span, vid, ty)) = VarPat(span, vid, doTy ty)
            | doPat(RecordPat{sourceSpan, fields, wildcard}) = RecordPat{sourceSpan=sourceSpan, fields=Syntax.mapRecordRow doPat fields, wildcard=wildcard}
            | doPat(ConPat{sourceSpan, longvid, payload, tyargs, isSoleConstructor}) = ConPat { sourceSpan = sourceSpan, longvid = longvid, payload = Option.map doPat payload, tyargs = List.map doTy tyargs, isSoleConstructor = isSoleConstructor }
            | doPat(TypedPat(span, pat, ty)) = TypedPat(span, doPat pat, doTy ty)
            | doPat(LayeredPat(span, vid, ty, pat)) = LayeredPat(span, vid, doTy ty, doPat pat)
          and doTypBind(TypBind(span, tyvars, tycon, ty)) = let val (subst, tyvars) = genFreshTyVars(subst, tyvars)
                                                            in TypBind(span, tyvars, tycon, applySubstTy subst ty)
                                                            end
          and doDatBind(DatBind(span, tyvars, tycon, conbinds, eq)) = let val (subst, tyvars) = genFreshTyVars(subst, tyvars)
                                                                          fun doConBind(ConBind(span, vid, optTy)) = ConBind(span, vid, Option.map (applySubstTy subst) optTy)
                                                                      in DatBind(span, tyvars, tycon, List.map doConBind conbinds, eq)
                                                                      end
          and doExBind(ExBind(span, vid, optTy)) = ExBind(span, vid, Option.map doTy optTy)
            | doExBind(ExReplication(span, vid, longvid, optTy)) = ExReplication(span, vid, longvid, Option.map doTy optTy)
          fun doTypeStructure { typeFunction = TypeFunction(tyvars, ty), valEnv }
              = { typeFunction = let val (subst, tyvars) = genFreshTyVars(subst, tyvars)
                                 in TypeFunction(tyvars, applySubstTy subst ty)
                                 end
                , valEnv = Syntax.VIdMap.map (fn (tysc, ids) => (doTypeScheme tysc, ids)) valEnv
                }
          fun doSignature({ valMap, tyConMap, strMap } : Signature) = { valMap = Syntax.VIdMap.map (fn (tysc, ids) => (doTypeScheme tysc, ids)) valMap
                                                                      , tyConMap = Syntax.TyConMap.map doTypeStructure tyConMap
                                                                      , strMap = Syntax.StrIdMap.map (fn MkSignature s => MkSignature (doSignature s)) strMap
                                                                      }
          fun doStrExp(StructExp { sourceSpan, valMap, tyConMap, strMap }) = StructExp { sourceSpan = sourceSpan, valMap = valMap, tyConMap = Syntax.TyConMap.map doTypeStructure tyConMap, strMap = strMap }
            | doStrExp(exp as StrIdExp _) = exp
            | doStrExp(LetInStrExp(span, strdecs, strexp)) = LetInStrExp(span, List.map doStrDec strdecs, doStrExp strexp)
          and doStrDec(CoreDec(span, dec)) = CoreDec(span, doDec dec)
            | doStrDec(StrBindDec(span, strid, strexp, s)) = StrBindDec(span, strid, doStrExp strexp, doSignature s)
            | doStrDec(GroupStrDec(span, decs)) = GroupStrDec(span, List.map doStrDec decs)
          fun doTopDec(StrDec strdec) = StrDec(doStrDec strdec)
      in { doExp = doExp
         , doDec = doDec
         , doDecs = List.map doDec
         , doUnaryConstraint = doUnaryConstraint
         , doTopDec = doTopDec
         , doTopDecs = List.map doTopDec
         }
      end

(* freeTyVarsInPat : TyVarSet * Pat -> TyVarSet *)
fun freeTyVarsInPat(bound, pat)
    = (case pat of
           WildcardPat _ => TyVarSet.empty
         | SConPat _ => TyVarSet.empty
         | VarPat(_, _, ty) => freeTyVarsInTy(bound, ty)
         | RecordPat{ fields = xs, ... } => List.foldl (fn ((_, pat), set) => TyVarSet.union(freeTyVarsInPat(bound, pat), set)) TyVarSet.empty xs
         | ConPat { payload = NONE, tyargs, ... } => List.foldl (fn (ty, set) => TyVarSet.union(freeTyVarsInTy(bound, ty), set)) TyVarSet.empty tyargs
         | ConPat { payload = SOME pat, tyargs, ... } => List.foldl (fn (ty, set) => TyVarSet.union(freeTyVarsInTy(bound, ty), set)) (freeTyVarsInPat(bound, pat)) tyargs
         | TypedPat(_, pat, ty) => TyVarSet.union(freeTyVarsInPat(bound, pat), freeTyVarsInTy(bound, ty))
         | LayeredPat(_, _, ty, pat) => TyVarSet.union(freeTyVarsInTy(bound, ty), freeTyVarsInPat(bound, pat))
      )

(* freeTyVarsInExp : TyVarSet * Exp -> TyVarSet *)
fun freeTyVarsInExp(bound, exp)
    = (case exp of
           SConExp _ => TyVarSet.empty
         | VarExp(_, _, _, tyargs) => List.foldl (fn ((ty,cts), set) => TyVarSet.union(freeTyVarsInTy(bound, ty), set)) TyVarSet.empty tyargs
         | RecordExp(_, xs) => List.foldl (fn ((_, exp), set) => TyVarSet.union(freeTyVarsInExp(bound, exp), set)) TyVarSet.empty xs
         | LetInExp(_, decls, exp) => TyVarSet.union(freeTyVarsInDecs(bound, decls), freeTyVarsInExp(bound, exp))
         | AppExp(_, exp1, exp2) => TyVarSet.union(freeTyVarsInExp(bound, exp1), freeTyVarsInExp(bound, exp2))
         | TypedExp(_, exp, ty) => TyVarSet.union(freeTyVarsInExp(bound, exp), freeTyVarsInTy(bound, ty))
         | HandleExp(_, exp, matches) => TyVarSet.union(freeTyVarsInExp(bound, exp), freeTyVarsInMatches(bound, matches, TyVarSet.empty))
         | RaiseExp(_, exp) => freeTyVarsInExp(bound, exp)
         | IfThenElseExp(_, exp1, exp2, exp3) => TyVarSet.union(freeTyVarsInExp(bound, exp1), TyVarSet.union(freeTyVarsInExp(bound, exp2), freeTyVarsInExp(bound, exp3)))
         | CaseExp(_, exp, ty, matches) => TyVarSet.union(freeTyVarsInExp(bound, exp), TyVarSet.union(freeTyVarsInTy(bound, ty), freeTyVarsInMatches(bound, matches, TyVarSet.empty)))
         | FnExp(_, vid, ty, body) => TyVarSet.union(freeTyVarsInTy(bound, ty), freeTyVarsInExp(bound, body))
         | ProjectionExp { recordTy = recordTy, fieldTy = fieldTy, ... } => TyVarSet.union(freeTyVarsInTy(bound, recordTy), freeTyVarsInTy(bound, fieldTy))
         | ListExp(_, xs, ty) => Vector.foldl (fn (x, set) => TyVarSet.union(freeTyVarsInExp(bound, x), set)) (freeTyVarsInTy(bound, ty)) xs
      )
and freeTyVarsInMatches(bound, nil, acc) = acc
  | freeTyVarsInMatches(bound, (pat, exp) :: rest, acc) = freeTyVarsInMatches(bound, rest, TyVarSet.union(acc, TyVarSet.union(freeTyVarsInPat(bound, pat), freeTyVarsInExp(bound, exp))))
and freeTyVarsInDecs(bound, decls) = List.foldl (fn (dec, set) => TyVarSet.union(set, freeTyVarsInDec(bound, dec))) TyVarSet.empty decls
and freeTyVarsInDec(bound, dec)
    = (case dec of
           ValDec(_, valbinds) => List.foldl (fn (valbind, acc) => TyVarSet.union(acc, freeTyVarsInValBind(bound, valbind))) TyVarSet.empty valbinds
         | RecValDec(_, valbinds) => List.foldl (fn (valbind, acc) => TyVarSet.union(acc, freeTyVarsInValBind(bound, valbind))) TyVarSet.empty valbinds
         | TypeDec(_, typbinds) => List.foldl (fn (typbind, acc) => TyVarSet.union(acc, freeTyVarsInTypBind(bound, typbind))) TyVarSet.empty typbinds
         | DatatypeDec(_, datbinds) => List.foldl (fn (datbind, acc) => TyVarSet.union(acc, freeTyVarsInDatBind(bound, datbind))) TyVarSet.empty datbinds
         | ExceptionDec(_, exbinds) => List.foldl (fn (exbind, acc) => TyVarSet.union(acc, freeTyVarsInExBind(bound, exbind))) TyVarSet.empty exbinds
         | GroupDec(_, decs) => freeTyVarsInDecs(bound, decs)
      )
and freeTyVarsInValBind(bound, TupleBind(_, xs, exp)) = List.foldl (fn ((_, ty), acc) => TyVarSet.union(acc, freeTyVarsInTy(bound, ty))) (freeTyVarsInExp(bound, exp)) xs
  | freeTyVarsInValBind(bound, PolyVarBind(_, vid, TypeScheme(tyvars, ty), exp)) = let val bound' = TyVarSet.addList(bound, List.map #1 tyvars)
                                                                                   in TyVarSet.union(freeTyVarsInTy(bound', ty), freeTyVarsInExp(bound', exp))
                                                                                   end
and freeTyVarsInTypBind(bound, TypBind(_, tyvars, tycon, ty)) = freeTyVarsInTy(TyVarSet.addList(bound, tyvars), ty)
and freeTyVarsInDatBind(bound, DatBind(_, tyvars, tycon, conbinds, _)) = let val bound' = TyVarSet.addList(bound, tyvars)
                                                                         in List.foldl (fn (conbind, acc) => TyVarSet.union(acc, freeTyVarsInConBind(bound', conbind))) TyVarSet.empty conbinds
                                                                         end
and freeTyVarsInConBind(bound, ConBind(_, vid, NONE)) = TyVarSet.empty
  | freeTyVarsInConBind(bound, ConBind(_, vid, SOME ty)) = freeTyVarsInTy(bound, ty)
and freeTyVarsInExBind(bound, ExBind(_, vid, NONE)) = TyVarSet.empty
  | freeTyVarsInExBind(bound, ExBind(_, vid, SOME ty)) = freeTyVarsInTy(bound, ty)
  | freeTyVarsInExBind(bound, ExReplication(_, _, _, NONE)) = TyVarSet.empty
  | freeTyVarsInExBind(bound, ExReplication(_, _, _, SOME ty)) = freeTyVarsInTy(bound, ty)
and freeTyVarsInUnaryConstraint(bound, unaryConstraint)
    = (case unaryConstraint of
           HasField{fieldTy = fieldTy, ...} => freeTyVarsInTy(bound, fieldTy)
         | IsEqType _    => TyVarSet.empty
         | IsIntegral _   => TyVarSet.empty
         | IsSignedReal _ => TyVarSet.empty
         | IsRing _       => TyVarSet.empty
         | IsField _      => TyVarSet.empty
         | IsSigned _     => TyVarSet.empty
         | IsOrdered _    => TyVarSet.empty
      )

fun freeTyVarsInSignature(bound, { valMap, tyConMap, strMap } : Signature) = TyVarSet.empty (* TODO: implement *)
fun freeTyVarsInStrExp(bound, StructExp { ... }) = TyVarSet.empty (* TODO: tyConMap *)
  | freeTyVarsInStrExp(bound, StrIdExp _) = TyVarSet.empty
  | freeTyVarsInStrExp(bound, LetInStrExp(_, strdecs, strexp)) = TyVarSet.union(freeTyVarsInStrDecs(bound, strdecs), freeTyVarsInStrExp(bound, strexp))
and freeTyVarsInStrDec(bound, CoreDec(_, dec)) = freeTyVarsInDec(bound, dec)
  | freeTyVarsInStrDec(bound, StrBindDec(_, _, strexp, s)) = TyVarSet.union(freeTyVarsInStrExp(bound, strexp), freeTyVarsInSignature(bound, s))
  | freeTyVarsInStrDec(bound, GroupStrDec(_, decs)) = freeTyVarsInStrDecs(bound, decs)
and freeTyVarsInStrDecs(bound, decs) = List.foldl (fn (dec, set) => TyVarSet.union(set, freeTyVarsInStrDec(bound, dec))) TyVarSet.empty decs

fun freeTyVarsInTopDec(bound, StrDec(strdec)) = freeTyVarsInStrDec(bound, strdec)
fun freeTyVarsInTopDecs(bound, decs) = List.foldl (fn (dec, set) => TyVarSet.union(set, freeTyVarsInTopDec(bound, dec))) TyVarSet.empty decs

(* filterVarsInPat : (VId -> bool) -> Pat -> Pat *)
fun filterVarsInPat pred =
    let fun doPat pat = case pat of
                            WildcardPat _ => pat
                          | SConPat _ => pat
                          | VarPat(span, vid, ty) => if pred vid then pat else WildcardPat span
                          | RecordPat{sourceSpan, fields, wildcard} => RecordPat{ sourceSpan = sourceSpan, fields = Syntax.mapRecordRow doPat fields, wildcard = wildcard }
                          | ConPat { payload = NONE, ... } => pat
                          | ConPat { sourceSpan, longvid, payload = SOME innerPat, tyargs, isSoleConstructor } => ConPat { sourceSpan = sourceSpan, longvid = longvid, payload = SOME (doPat innerPat), tyargs = tyargs, isSoleConstructor = isSoleConstructor }
                          | TypedPat(span, innerPat, ty) => TypedPat(span, doPat innerPat, ty)
                          | LayeredPat(span, vid, ty, innerPat) => if pred vid then LayeredPat(span, vid, ty, doPat innerPat) else TypedPat(span, doPat innerPat, ty)
    in doPat
    end

(* renameVarsInPat : VId VIdMap.map -> Pat -> Pat *)
fun renameVarsInPat m =
    let fun doPat (pat as WildcardPat _) = pat
          | doPat (pat as SConPat _) = pat
          | doPat (pat as VarPat(span, vid, ty)) = (case VIdMap.find(m, vid) of
                                                        NONE => pat
                                                      | SOME repl => VarPat(span, repl, ty)
                                                   )
          | doPat (RecordPat { sourceSpan, fields, wildcard }) = RecordPat { sourceSpan = sourceSpan
                                                                           , fields = List.map (fn (label, pat) => (label, doPat pat)) fields
                                                                           , wildcard = wildcard
                                                                           }
          | doPat (ConPat { sourceSpan, longvid, payload, tyargs, isSoleConstructor }) = ConPat { sourceSpan = sourceSpan, longvid = longvid, payload = Option.map doPat payload, tyargs = tyargs, isSoleConstructor = isSoleConstructor }
          | doPat (TypedPat(span, pat, ty)) = TypedPat(span, doPat pat, ty)
          | doPat (LayeredPat(span, vid, ty, pat)) = LayeredPat(span, case VIdMap.find(m, vid) of
                                                                          NONE => vid
                                                                        | SOME repl => repl
                                                                , ty, doPat pat)
    in doPat
    end
end (* structure USyntax *)
