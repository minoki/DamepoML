(*
 * Copyright (c) 2021 ARATA Mizuki
 * This file is part of LunarML.
 *)
structure FSyntax = struct
type TyVar = USyntax.TyVar
type TyName = USyntax.TyName
datatype SLabel = ValueLabel of Syntax.VId
                | StructLabel of Syntax.StrId
                | ExnTagLabel of Syntax.VId (* of constructor *)
                | EqualityLabel of Syntax.TyCon
datatype Path = Root of USyntax.VId
              | Child of Path * SLabel
datatype Ty = TyVar of TyVar
            | RecordType of (Syntax.Label * Ty) list
            | TyCon of Ty list * TyName
            | FnType of Ty * Ty
            | ForallType of TyVar * Ty
            (* TypeFn : (TyVar * Kind) list * Ty *)
            (* ExistsType of (TyVar * Kind) * Ty *)
            | SigType of { valMap : Ty Syntax.VIdMap.map (* id status? *)
                         , strMap : Ty Syntax.StrIdMap.map
                         , exnTags : Syntax.VIdSet.set
                         , equalityMap : Ty Syntax.TyConMap.map
                         }
datatype Pat = WildcardPat
             | SConPat of Syntax.SCon
             | VarPat of USyntax.VId * Ty
             | RecordPat of (Syntax.Label * Pat) list * bool
             | ConPat of Path * Pat option * Ty list
             | LayeredPat of USyntax.VId * Ty * Pat
datatype ConBind = ConBind of USyntax.VId * Ty option
datatype DatBind = DatBind of TyVar list * TyName * ConBind list
datatype Exp = SConExp of Syntax.SCon
             | VarExp of USyntax.VId
             | RecordExp of (Syntax.Label * Exp) list
             | LetExp of Dec * Exp
             | AppExp of Exp * Exp
             | HandleExp of { body : Exp
                            , exnName : USyntax.VId
                            , handler : Exp
                            }
             | RaiseExp of SourcePos.span * Exp
             | IfThenElseExp of Exp * Exp * Exp
             | CaseExp of SourcePos.span * Exp * Ty * (Pat * Exp) list
             | FnExp of USyntax.VId * Ty * Exp
             | ProjectionExp of { label : Syntax.Label, recordTy : Ty, fieldTy : Ty }
             | ListExp of Exp vector * Ty
             | VectorExp of Exp vector * Ty
             | TyAbsExp of TyVar * Exp
             | TyAppExp of Exp * Ty
             | RecordEqualityExp of (Syntax.Label * Exp) list
             | DataTagExp of Exp (* * TyName *)
             | DataPayloadExp of Exp (* * USyntax.LongVId * TyName *)
             | StructExp of { valMap : Path Syntax.VIdMap.map
                            , strMap : Path Syntax.StrIdMap.map
                            , exnTagMap : Path Syntax.VIdMap.map
                            , equalityMap : Path Syntax.TyConMap.map
                            }
             | SProjectionExp of Exp * SLabel
     (* PackExp *)
     and ValBind = SimpleBind of USyntax.VId * Ty * Exp
                 | TupleBind of (USyntax.VId * Ty) list * Exp
                 (* UnpackingBind *)
     and Dec = ValDec of ValBind
             | RecValDec of ValBind list
             | IgnoreDec of Exp (* val _ = ... *)
             | DatatypeDec of DatBind list
             | ExceptionDec of { conName : USyntax.VId, tagName : USyntax.VId, payloadTy : Ty option }
             | ExceptionRepDec of { conName : USyntax.VId, conPath : Path, tagPath : Path, payloadTy : Ty option }
             | ExportValue of Exp
             | ExportModule of (string * Exp) vector
             | GroupDec of USyntax.VIdSet.set option * Dec list
fun PairType(a, b) = RecordType [(Syntax.NumericLabel 1, a), (Syntax.NumericLabel 2, b)]
fun TuplePat xs = let fun doFields i nil = nil
                        | doFields i (x :: xs) = (Syntax.NumericLabel i, x) :: doFields (i + 1) xs
                  in RecordPat (doFields 1 xs, false)
                  end
fun TupleExp xs = let fun doFields i nil = nil
                        | doFields i (x :: xs) = (Syntax.NumericLabel i, x) :: doFields (i + 1) xs
                  in RecordExp (doFields 1 xs)
                  end
fun strIdToVId(USyntax.MkStrId(name, n)) = USyntax.MkVId(name, n)
fun LongVarExp(USyntax.MkShortVId vid) = VarExp vid
  | LongVarExp(USyntax.MkLongVId(strid0, strids, vid)) = SProjectionExp (List.foldl (fn (label, x) => SProjectionExp (x, StructLabel label)) (VarExp (strIdToVId strid0)) strids, ValueLabel vid)
fun PathToExp(Root vid) = VarExp vid
  | PathToExp(Child (parent, label)) = SProjectionExp (PathToExp parent, label)
fun rootOfPath(Root vid) = vid
  | rootOfPath(Child (parent, _)) = rootOfPath parent
fun AndalsoExp(a, b) = IfThenElseExp(a, b, VarExp(InitialEnv.VId_false))
fun SimplifyingAndalsoExp(a as VarExp(vid), b) = if USyntax.eqVId(vid, InitialEnv.VId_true) then
                                                     b
                                                 else if USyntax.eqVId(vid, InitialEnv.VId_false) then
                                                     a
                                                 else
                                                     AndalsoExp(a, b)
  | SimplifyingAndalsoExp(a, b as VarExp(vid)) = if USyntax.eqVId(vid, InitialEnv.VId_true) then
                                                     a
                                                 else
                                                     AndalsoExp(a, b)
  | SimplifyingAndalsoExp(a, b) = AndalsoExp(a, b)

(* occurCheck : TyVar -> Ty -> bool *)
fun occurCheck tv =
    let fun check (TyVar tv') = USyntax.eqUTyVar(tv, tv')
          | check (RecordType xs) = List.exists (fn (label, ty) => check ty) xs
          | check (TyCon(tyargs, tyname)) = List.exists check tyargs
          | check (FnType(ty1, ty2)) = check ty1 orelse check ty2
          | check (ForallType(tv', ty)) = if USyntax.eqUTyVar(tv, tv') then
                                              false
                                          else
                                              check ty
          | check (SigType { valMap, strMap, exnTags, equalityMap }) = Syntax.VIdMap.exists check valMap orelse Syntax.StrIdMap.exists check strMap orelse Syntax.TyConMap.exists check equalityMap
    in check
    end

(* substituteTy : TyVar * Ty -> Ty -> Ty *)
fun substituteTy (tv, replacement) =
    let fun go (ty as TyVar tv') = if USyntax.eqUTyVar(tv, tv') then
                                       replacement
                                   else
                                       ty
          | go (RecordType fields) = RecordType (Syntax.mapRecordRow go fields)
          | go (TyCon(tyargs, tyname)) = TyCon(List.map go tyargs, tyname)
          | go (FnType(ty1, ty2)) = FnType(go ty1, go ty2)
          | go (ty as ForallType(tv', ty')) = if USyntax.eqUTyVar(tv, tv') then
                                                  ty
                                              else if occurCheck tv' replacement then
                                                  (* TODO: generate fresh type variable *)
                                                  let val tv'' = raise Fail "FSyntax.substituteTy: not implemented yet"
                                                  in ForallType(tv'', go (substituteTy (tv', TyVar tv'') ty'))
                                                  end
                                              else
                                                  ForallType(tv', go ty')
          | go (SigType { valMap, strMap, exnTags, equalityMap }) = SigType { valMap = Syntax.VIdMap.map go valMap
                                                                            , strMap = Syntax.StrIdMap.map go strMap
                                                                            , exnTags = exnTags
                                                                            , equalityMap = Syntax.TyConMap.map go equalityMap
                                                                            }
    in go
    end

(* substTy : Ty TyVarMap.map -> { doTy : Ty -> Ty, doConBind : ConBind -> ConBind, doPat : Pat -> Pat, doExp : Exp -> Exp, doDec : Dec -> Dec, doDecs : Decs -> Decs } *)
fun substTy (subst : Ty USyntax.TyVarMap.map) =
    let fun doTy (ty as TyVar tv) = (case USyntax.TyVarMap.find(subst, tv) of
                                         NONE => ty
                                       | SOME replacement => replacement
                                    )
          | doTy (RecordType fields) = RecordType (List.map (fn (label, ty) => (label, doTy ty)) fields)
          | doTy (TyCon (tyargs, tyname)) = TyCon (List.map doTy tyargs, tyname)
          | doTy (FnType (ty1, ty2)) = FnType (doTy ty1, doTy ty2)
          | doTy (ForallType (tv, ty)) = if USyntax.TyVarMap.inDomain (subst, tv) then (* TODO: use fresh tyvar if necessary *)
                                             ForallType (tv, #doTy (substTy (#1 (USyntax.TyVarMap.remove (subst, tv)))) ty)
                                         else
                                             ForallType (tv, doTy ty)
          | doTy (SigType { valMap, strMap, exnTags, equalityMap }) = SigType { valMap = Syntax.VIdMap.map doTy valMap
                                                                              , strMap = Syntax.StrIdMap.map doTy strMap
                                                                              , exnTags = exnTags
                                                                              , equalityMap = Syntax.TyConMap.map doTy equalityMap
                                                                              }
        fun doPat (pat as WildcardPat) = pat
          | doPat (pat as SConPat _) = pat
          | doPat (VarPat (vid, ty)) = VarPat (vid, doTy ty)
          | doPat (RecordPat (fields, wildcard)) = RecordPat (List.map (fn (label, pat) => (label, doPat pat)) fields, wildcard)
          | doPat (ConPat (path, optPat, tyargs)) = ConPat (path, Option.map doPat optPat, List.map doTy tyargs)
          | doPat (LayeredPat (vid, ty, pat)) = LayeredPat (vid, doTy ty, doPat pat)
        fun doConBind (ConBind (vid, optTy)) = ConBind (vid, Option.map doTy optTy)
        fun doDatBind (DatBind (tyvars, tyname, conbinds)) = let val subst' = List.foldl (fn (tv, subst) => if USyntax.TyVarMap.inDomain (subst, tv) then #1 (USyntax.TyVarMap.remove (subst, tv)) else subst) subst tyvars (* TODO: use fresh tyvar if necessary *)
                                                             in DatBind (tyvars, tyname, List.map (#doConBind (substTy subst')) conbinds)
                                                             end
        fun doExp (exp as SConExp _) = exp
          | doExp (exp as VarExp _) = exp
          | doExp (RecordExp fields) = RecordExp (List.map (fn (label, exp) => (label, doExp exp)) fields)
          | doExp (LetExp (dec, exp)) = LetExp (doDec dec, doExp exp)
          | doExp (AppExp (exp1, exp2)) = AppExp (doExp exp1, doExp exp2)
          | doExp (HandleExp { body, exnName, handler }) = HandleExp { body = doExp body, exnName = exnName, handler = doExp handler }
          | doExp (RaiseExp (span, exp)) = RaiseExp (span, doExp exp)
          | doExp (IfThenElseExp (exp1, exp2, exp3)) = IfThenElseExp (doExp exp1, doExp exp2, doExp exp3)
          | doExp (CaseExp (span, exp, ty, matches)) = CaseExp (span, doExp exp, doTy ty, List.map (fn (pat, exp) => (doPat pat, doExp exp)) matches)
          | doExp (FnExp (vid, ty, exp)) = FnExp (vid, doTy ty, doExp exp)
          | doExp (ProjectionExp { label, recordTy, fieldTy }) = ProjectionExp { label = label, recordTy = doTy recordTy, fieldTy = doTy fieldTy }
          | doExp (ListExp (xs, ty)) = ListExp (Vector.map doExp xs, doTy ty)
          | doExp (VectorExp (xs, ty)) = VectorExp (Vector.map doExp xs, doTy ty)
          | doExp (TyAbsExp (tv, exp)) = if USyntax.TyVarMap.inDomain (subst, tv) then (* TODO: use fresh tyvar if necessary *)
                                             TyAbsExp (tv, #doExp (substTy (#1 (USyntax.TyVarMap.remove (subst, tv)))) exp)
                                         else
                                             TyAbsExp (tv, doExp exp)
          | doExp (TyAppExp (exp, ty)) = TyAppExp (doExp exp, doTy ty)
          | doExp (RecordEqualityExp fields) = RecordEqualityExp (List.map (fn (label, exp) => (label, doExp exp)) fields)
          | doExp (DataTagExp exp) = DataTagExp (doExp exp)
          | doExp (DataPayloadExp exp) = DataPayloadExp (doExp exp)
          | doExp (StructExp { valMap, strMap, exnTagMap, equalityMap }) = StructExp { valMap = valMap
                                                                                     , strMap = strMap
                                                                                     , exnTagMap = exnTagMap
                                                                                     , equalityMap = equalityMap
                                                                                     }
          | doExp (SProjectionExp (exp, label)) = SProjectionExp (doExp exp, label)
        and doDec (ValDec valbind) = ValDec (doValBind valbind)
          | doDec (RecValDec valbinds) = RecValDec (List.map doValBind valbinds)
          | doDec (IgnoreDec exp) = IgnoreDec (doExp exp)
          | doDec (DatatypeDec datbinds) = DatatypeDec (List.map doDatBind datbinds)
          | doDec (ExceptionDec { conName, tagName, payloadTy }) = ExceptionDec { conName = conName, tagName = tagName, payloadTy = Option.map doTy payloadTy }
          | doDec (ExceptionRepDec { conName, conPath, tagPath, payloadTy }) = ExceptionRepDec { conName = conName, conPath = conPath, tagPath = tagPath, payloadTy = Option.map doTy payloadTy }
          | doDec (ExportValue exp) = ExportValue (doExp exp)
          | doDec (ExportModule fields) = ExportModule (Vector.map (fn (label, exp) => (label, doExp exp)) fields)
          | doDec (GroupDec (vars, decs)) = GroupDec (vars, List.map doDec decs)
        and doValBind (SimpleBind (vid, ty, exp)) = SimpleBind (vid, doTy ty, doExp exp)
          | doValBind (TupleBind (binds, exp)) = TupleBind (List.map (fn (vid, ty) => (vid, doTy ty)) binds, doExp exp)
    in { doTy = doTy
       , doConBind = doConBind
       , doPat = doPat
       , doExp = doExp
       , doDec = doDec
       , doDecs = List.map doDec
       }
    end

fun freeTyVarsInTy (bound : USyntax.TyVarSet.set, TyVar tv) = if USyntax.TyVarSet.member (bound, tv) then
                                                                  USyntax.TyVarSet.empty
                                                              else
                                                                  USyntax.TyVarSet.singleton tv
  | freeTyVarsInTy (bound, RecordType fields) = List.foldl (fn ((label, ty), acc) => USyntax.TyVarSet.union (acc, freeTyVarsInTy (bound, ty))) USyntax.TyVarSet.empty fields
  | freeTyVarsInTy (bound, TyCon (tyargs, tyname)) = List.foldl (fn (ty, acc) => USyntax.TyVarSet.union (acc, freeTyVarsInTy (bound, ty))) USyntax.TyVarSet.empty tyargs
  | freeTyVarsInTy (bound, FnType (ty1, ty2)) = USyntax.TyVarSet.union (freeTyVarsInTy (bound, ty1), freeTyVarsInTy (bound, ty2))
  | freeTyVarsInTy (bound, ForallType (tv, ty)) = freeTyVarsInTy (USyntax.TyVarSet.add (bound, tv), ty)
  | freeTyVarsInTy (bound, SigType { valMap, strMap, exnTags, equalityMap }) = let val acc = Syntax.VIdMap.foldl (fn (ty, acc) => USyntax.TyVarSet.union (acc, freeTyVarsInTy (bound, ty))) USyntax.TyVarSet.empty valMap
                                                                                   val acc = Syntax.StrIdMap.foldl (fn (ty, acc) => USyntax.TyVarSet.union (acc, freeTyVarsInTy (bound, ty))) acc strMap
                                                                               in Syntax.TyConMap.foldl (fn (ty, acc) => USyntax.TyVarSet.union (acc, freeTyVarsInTy (bound, ty))) acc equalityMap
                                                                               end
fun freeTyVarsInPat (bound, WildcardPat) = USyntax.TyVarSet.empty
  | freeTyVarsInPat (bound, SConPat _) = USyntax.TyVarSet.empty
  | freeTyVarsInPat (bound, VarPat (vid, ty)) = freeTyVarsInTy (bound, ty)
  | freeTyVarsInPat (bound, RecordPat (fields, wildcard)) = List.foldl (fn ((label, pat), acc) => USyntax.TyVarSet.union (acc, freeTyVarsInPat (bound, pat))) USyntax.TyVarSet.empty fields
  | freeTyVarsInPat (bound, ConPat (path, NONE, tyargs)) = List.foldl (fn (ty, acc) => USyntax.TyVarSet.union (acc, freeTyVarsInTy (bound, ty))) USyntax.TyVarSet.empty tyargs
  | freeTyVarsInPat (bound, ConPat (path, SOME innerPat, tyargs)) = List.foldl (fn (ty, acc) => USyntax.TyVarSet.union (acc, freeTyVarsInTy (bound, ty))) (freeTyVarsInPat (bound, innerPat)) tyargs
  | freeTyVarsInPat (bound, LayeredPat (_, ty, innerPat)) = USyntax.TyVarSet.union (freeTyVarsInTy (bound, ty), freeTyVarsInPat (bound, innerPat))
fun freeTyVarsInExp (bound : USyntax.TyVarSet.set, SConExp _) = USyntax.TyVarSet.empty
  | freeTyVarsInExp (bound, VarExp _) = USyntax.TyVarSet.empty
  | freeTyVarsInExp (bound, RecordExp fields) = List.foldl (fn ((label, exp), acc) => USyntax.TyVarSet.union (acc, freeTyVarsInExp (bound, exp))) USyntax.TyVarSet.empty fields
  | freeTyVarsInExp (bound, LetExp (dec, exp)) = USyntax.TyVarSet.union (freeTyVarsInDec (bound, dec), freeTyVarsInExp (bound, exp))
  | freeTyVarsInExp (bound, AppExp (exp1, exp2)) = USyntax.TyVarSet.union (freeTyVarsInExp (bound, exp1), freeTyVarsInExp (bound, exp2))
  | freeTyVarsInExp (bound, HandleExp { body, exnName, handler }) = USyntax.TyVarSet.union (freeTyVarsInExp (bound, body), freeTyVarsInExp (bound, handler))
  | freeTyVarsInExp (bound, RaiseExp (span, exp)) = freeTyVarsInExp (bound, exp)
  | freeTyVarsInExp (bound, IfThenElseExp (exp1, exp2, exp3)) = USyntax.TyVarSet.union (freeTyVarsInExp (bound, exp1), USyntax.TyVarSet.union (freeTyVarsInExp (bound, exp2), freeTyVarsInExp (bound, exp3)))
  | freeTyVarsInExp (bound, CaseExp (span, exp, ty, matches)) = let val acc = freeTyVarsInExp (bound, exp)
                                                                    val acc = USyntax.TyVarSet.union (acc, freeTyVarsInTy (bound, ty))
                                                                in List.foldl (fn ((pat, exp), acc) => USyntax.TyVarSet.union (USyntax.TyVarSet.union (acc, freeTyVarsInPat (bound, pat)), freeTyVarsInExp (bound, exp))) acc matches
                                                                end
  | freeTyVarsInExp (bound, FnExp (vid, ty, exp)) = USyntax.TyVarSet.union (freeTyVarsInTy (bound, ty), freeTyVarsInExp (bound, exp))
  | freeTyVarsInExp (bound, ProjectionExp { label, recordTy, fieldTy }) = USyntax.TyVarSet.union (freeTyVarsInTy (bound, recordTy), freeTyVarsInTy (bound, fieldTy))
  | freeTyVarsInExp (bound, ListExp (xs, ty)) = Vector.foldl (fn (exp, acc) => USyntax.TyVarSet.union (acc, freeTyVarsInExp (bound, exp))) (freeTyVarsInTy (bound, ty)) xs
  | freeTyVarsInExp (bound, VectorExp (xs, ty)) = Vector.foldl (fn (exp, acc) => USyntax.TyVarSet.union (acc, freeTyVarsInExp (bound, exp))) (freeTyVarsInTy (bound, ty)) xs
  | freeTyVarsInExp (bound, TyAbsExp (tv, exp)) = freeTyVarsInExp (USyntax.TyVarSet.add (bound, tv), exp)
  | freeTyVarsInExp (bound, TyAppExp (exp, ty)) = USyntax.TyVarSet.union (freeTyVarsInExp (bound, exp), freeTyVarsInTy (bound, ty))
  | freeTyVarsInExp (bound, RecordEqualityExp fields) = List.foldl (fn ((label, exp), acc) => USyntax.TyVarSet.union (acc, freeTyVarsInExp (bound, exp))) USyntax.TyVarSet.empty fields
  | freeTyVarsInExp (bound, DataTagExp exp) = freeTyVarsInExp (bound, exp)
  | freeTyVarsInExp (bound, DataPayloadExp exp) = freeTyVarsInExp (bound, exp)
  | freeTyVarsInExp (bound, StructExp { valMap, strMap, exnTagMap, equalityMap }) = USyntax.TyVarSet.empty
  | freeTyVarsInExp (bound, SProjectionExp (exp, label)) = freeTyVarsInExp (bound, exp)
and freeTyVarsInValBind (bound, SimpleBind (vid, ty, exp)) = USyntax.TyVarSet.union (freeTyVarsInTy (bound, ty), freeTyVarsInExp (bound, exp))
  | freeTyVarsInValBind (bound, TupleBind (binds, exp)) = List.foldl (fn ((vid, ty), acc) => USyntax.TyVarSet.union (acc, freeTyVarsInTy (bound, ty))) (freeTyVarsInExp (bound, exp)) binds
and freeTyVarsInDec (bound, ValDec valbind) = freeTyVarsInValBind (bound, valbind)
  | freeTyVarsInDec (bound, RecValDec valbinds) = List.foldl (fn (valbind, acc) => USyntax.TyVarSet.union (acc, freeTyVarsInValBind (bound, valbind))) USyntax.TyVarSet.empty valbinds
  | freeTyVarsInDec (bound, IgnoreDec exp) = freeTyVarsInExp (bound, exp)
  | freeTyVarsInDec (bound, DatatypeDec datbinds) = List.foldl (fn (DatBind (tyvars, tyname, conbinds), acc) =>
                                                                   let val bound = USyntax.TyVarSet.addList (bound, tyvars)
                                                                   in List.foldl (fn (ConBind (vid, NONE), acc) => acc
                                                                                 | (ConBind (vid, SOME ty), acc) => USyntax.TyVarSet.union (acc, freeTyVarsInTy (bound, ty))
                                                                                 ) acc conbinds
                                                                   end
                                                               ) USyntax.TyVarSet.empty datbinds
  | freeTyVarsInDec (bound, ExceptionDec { conName, tagName, payloadTy }) = (case payloadTy of
                                                                                 NONE => USyntax.TyVarSet.empty
                                                                               | SOME payloadTy => freeTyVarsInTy (bound, payloadTy)
                                                                            )
  | freeTyVarsInDec (bound, ExceptionRepDec { conName, conPath, tagPath, payloadTy }) = (case payloadTy of
                                                                                             NONE => USyntax.TyVarSet.empty
                                                                                           | SOME payloadTy => freeTyVarsInTy (bound, payloadTy)
                                                                                        )
  | freeTyVarsInDec (bound, ExportValue exp) = freeTyVarsInExp (bound, exp)
  | freeTyVarsInDec (bound, ExportModule exports) = Vector.foldl (fn ((name, exp), acc) => USyntax.TyVarSet.union (acc, freeTyVarsInExp (bound, exp))) USyntax.TyVarSet.empty exports
  | freeTyVarsInDec (bound, GroupDec (v, decs)) = freeTyVarsInDecs (bound, decs)
and freeTyVarsInDecs (bound, decs) = List.foldl (fn (dec, acc) => USyntax.TyVarSet.union (acc, freeTyVarsInDec (bound, dec))) USyntax.TyVarSet.empty decs

local
    fun isLongStrId(VarExp(USyntax.MkVId(name, n)), USyntax.MkStrId(name', n'), []) = n = n' andalso name = name'
      | isLongStrId(SProjectionExp(exp, StructLabel strid), strid0, stridLast :: strids) = strid = stridLast andalso isLongStrId(exp, strid0, strids)
      | isLongStrId(_, _, _) = false
in
    fun isLongVId(VarExp vid, USyntax.MkShortVId vid') = USyntax.eqVId(vid, vid')
      | isLongVId(SProjectionExp(exp, ValueLabel vid), USyntax.MkLongVId(strid0, strids, vid')) = vid = vid' andalso isLongStrId(exp, strid0, List.rev strids)
      | isLongVId(_, _) = false
end

structure PrettyPrint = struct
val print_TyVar = USyntax.print_TyVar
val print_VId = USyntax.print_VId
val print_LongVId = USyntax.print_LongVId
val print_TyName = USyntax.print_TyName
fun print_Path (Root vid) = USyntax.print_VId vid
  | print_Path (Child (parent, label)) = print_Path parent ^ "/.." (* TODO *)
fun print_Ty (TyVar x) = "TyVar(" ^ print_TyVar x ^ ")"
  | print_Ty (RecordType xs) = (case Syntax.extractTuple (1, xs) of
                                    NONE => "RecordType " ^ Syntax.print_list (Syntax.print_pair (Syntax.print_Label,print_Ty)) xs
                                  | SOME ys => "TupleType " ^ Syntax.print_list print_Ty ys
                               )
  | print_Ty (TyCon([],USyntax.MkTyName("int", 0))) = "primTy_int"
  | print_Ty (TyCon([],USyntax.MkTyName("word", 1))) = "primTy_word"
  | print_Ty (TyCon([],USyntax.MkTyName("real", 2))) = "primTy_real"
  | print_Ty (TyCon([],USyntax.MkTyName("string", 3))) = "primTy_string"
  | print_Ty (TyCon([],USyntax.MkTyName("char", 4))) = "primTy_char"
  | print_Ty (TyCon([],USyntax.MkTyName("exn", 5))) = "primTy_exn"
  | print_Ty (TyCon([],USyntax.MkTyName("bool", 6))) = "primTy_bool"
  | print_Ty (TyCon(x,y)) = "TyCon(" ^ Syntax.print_list print_Ty x ^ "," ^ print_TyName y ^ ")"
  | print_Ty (FnType(x,y)) = "FnType(" ^ print_Ty x ^ "," ^ print_Ty y ^ ")"
  | print_Ty (ForallType(tv,x)) = "ForallType(" ^ print_TyVar tv ^ "," ^ print_Ty x ^ ")"
  | print_Ty (SigType _) = "SigType"
fun print_Pat WildcardPat = "WildcardPat"
  | print_Pat (SConPat x) = "SConPat(" ^ Syntax.print_SCon x ^ ")"
  | print_Pat (VarPat(vid, ty)) = "VarPat(" ^ print_VId vid ^ "," ^ print_Ty ty ^ ")"
  | print_Pat (LayeredPat (vid, ty, pat)) = "TypedPat(" ^ print_VId vid ^ "," ^ print_Ty ty ^ "," ^ print_Pat pat ^ ")"
  | print_Pat (ConPat(path, pat, tyargs)) = "ConPat(" ^ print_Path path ^ "," ^ Syntax.print_option print_Pat pat ^ "," ^ Syntax.print_list print_Ty tyargs ^ ")"
  | print_Pat (RecordPat(x, false)) = (case Syntax.extractTuple (1, x) of
                                           NONE => "RecordPat(" ^ Syntax.print_list (Syntax.print_pair (Syntax.print_Label, print_Pat)) x ^ ",false)"
                                         | SOME ys => "TuplePat " ^ Syntax.print_list print_Pat ys
                                      )
  | print_Pat (RecordPat(x, true)) = "RecordPat(" ^ Syntax.print_list (Syntax.print_pair (Syntax.print_Label, print_Pat)) x ^ ",true)"
fun print_Exp (SConExp x) = "SConExp(" ^ Syntax.print_SCon x ^ ")"
  | print_Exp (VarExp(x)) = "VarExp(" ^ print_VId x ^ ")"
  | print_Exp (RecordExp x) = (case Syntax.extractTuple (1, x) of
                                   NONE => "RecordExp " ^ Syntax.print_list (Syntax.print_pair (Syntax.print_Label, print_Exp)) x
                                 | SOME ys => "TupleExp " ^ Syntax.print_list print_Exp ys
                              )
  | print_Exp (LetExp(dec,x)) = "LetExp(" ^ print_Dec dec ^ "," ^ print_Exp x ^ ")"
  | print_Exp (AppExp(x,y)) = "AppExp(" ^ print_Exp x ^ "," ^ print_Exp y ^ ")"
  | print_Exp (HandleExp{body,exnName,handler}) = "HandleExp{body=" ^ print_Exp body ^ ",exnName=" ^ USyntax.print_VId exnName ^ ",handler=" ^ print_Exp handler ^ ")"
  | print_Exp (RaiseExp(span,x)) = "RaiseExp(" ^ print_Exp x ^ ")"
  | print_Exp (IfThenElseExp(x,y,z)) = "IfThenElseExp(" ^ print_Exp x ^ "," ^ print_Exp y ^ "," ^ print_Exp z ^ ")"
  | print_Exp (CaseExp(_,x,ty,y)) = "CaseExp(" ^ print_Exp x ^ "," ^ print_Ty ty ^ "," ^ Syntax.print_list (Syntax.print_pair (print_Pat,print_Exp)) y ^ ")"
  | print_Exp (FnExp(pname,pty,body)) = "FnExp(" ^ print_VId pname ^ "," ^ print_Ty pty ^ "," ^ print_Exp body ^ ")"
  | print_Exp (ProjectionExp { label = label, recordTy = recordTy, fieldTy = fieldTy }) = "ProjectionExp{label=" ^ Syntax.print_Label label ^ ",recordTy=" ^ print_Ty recordTy ^ ",fieldTy=" ^ print_Ty fieldTy ^ "}"
  | print_Exp (ListExp _) = "ListExp"
  | print_Exp (VectorExp _) = "VectorExp"
  | print_Exp (TyAbsExp(tv, exp)) = "TyAbsExp(" ^ print_TyVar tv ^ "," ^ print_Exp exp ^ ")"
  | print_Exp (TyAppExp(exp, ty)) = "TyAppExp(" ^ print_Exp exp ^ "," ^ print_Ty ty ^ ")"
  | print_Exp (RecordEqualityExp(fields)) = "RecordEqualityExp(" ^ Syntax.print_list (Syntax.print_pair (Syntax.print_Label, print_Exp)) fields ^ ")"
  | print_Exp (DataTagExp exp) = "DataTagExp(" ^ print_Exp exp ^ ")"
  | print_Exp (DataPayloadExp exp) = "DataPayloadExp(" ^ print_Exp exp ^ ")"
  | print_Exp (StructExp _) = "StructExp"
  | print_Exp (SProjectionExp _) = "SProjectionExp"
and print_ValBind (SimpleBind (v, ty, exp)) = "SimpleBind(" ^ print_VId v ^ "," ^ print_Ty ty ^ "," ^ print_Exp exp ^ ")"
  | print_ValBind (TupleBind (xs, exp)) = "TupleBind(" ^ Syntax.print_list (Syntax.print_pair (print_VId, print_Ty)) xs ^ "," ^ print_Exp exp ^ ")"
and print_Dec (ValDec (valbind)) = "ValDec(" ^ print_ValBind valbind ^ ")"
  | print_Dec (RecValDec (valbinds)) = "RecValDec(" ^ Syntax.print_list print_ValBind valbinds ^ ")"
  | print_Dec (IgnoreDec exp) = "IgnoreDec(" ^ print_Exp exp ^ ")"
  | print_Dec (DatatypeDec datbinds) = "DatatypeDec"
  | print_Dec (ExceptionDec _) = "ExceptionDec"
  | print_Dec (ExceptionRepDec _) = "ExceptionRepDec"
  | print_Dec (ExportValue _) = "ExportValue"
  | print_Dec (ExportModule _) = "ExportModule"
  | print_Dec (GroupDec _) = "GroupDec"
val print_Decs = Syntax.print_list print_Dec
end (* structure PrettyPrint *)
end (* structure FSyntax *)

structure ToFSyntax = struct
fun LongStrIdExp(USyntax.MkLongStrId(strid0, strids)) = List.foldl (fn (label, x) => FSyntax.SProjectionExp (x, FSyntax.StructLabel label)) (FSyntax.VarExp (FSyntax.strIdToVId strid0)) strids

fun LongVIdToPath(USyntax.MkLongVId(strid0, strids, vid)) = FSyntax.Child (List.foldl (fn (strid, p) => FSyntax.Child(p, FSyntax.StructLabel strid)) (FSyntax.Root (FSyntax.strIdToVId strid0)) strids, FSyntax.ValueLabel vid)
  | LongVIdToPath(USyntax.MkShortVId vid) = FSyntax.Root vid
fun LongStrIdToPath(USyntax.MkLongStrId(strid0, strids)) = List.foldl (fn (strid, p) => FSyntax.Child(p, FSyntax.StructLabel strid)) (FSyntax.Root (FSyntax.strIdToVId strid0)) strids

type Context = { nextVId : int ref
               }
type Env = { equalityForTyVarMap : USyntax.VId USyntax.TyVarMap.map
           , equalityForTyNameMap : USyntax.LongVId USyntax.TyNameMap.map
           , exnTagMap : FSyntax.Path USyntax.LongVIdMap.map
           }
val initialEnv : Env = { equalityForTyVarMap = USyntax.TyVarMap.empty
                       , equalityForTyNameMap = let open Typing InitialEnv
                                                in List.foldl USyntax.TyNameMap.insert' USyntax.TyNameMap.empty
                                                              [(primTyName_int, VId_EQUAL_int)
                                                              ,(primTyName_word, VId_EQUAL_word)
                                                              ,(primTyName_string, VId_EQUAL_string)
                                                              ,(primTyName_char, VId_EQUAL_char)
                                                              ,(primTyName_bool, VId_EQUAL_bool)
                                                              ,(primTyName_list, VId_EQUAL_list)
                                                              ,(primTyName_vector, VId_EQUAL_vector)
                                                              ]
                                                end
                       , exnTagMap = let open InitialEnv
                                     in List.foldl (fn ((con, tag), m) => USyntax.LongVIdMap.insert(m, con, LongVIdToPath tag)) USyntax.LongVIdMap.empty
                                                   [(LongVId_Match, VId_Match_tag)
                                                   ,(LongVId_Bind, VId_Bind_tag)
                                                   ,(LongVId_Div, VId_Div_tag)
                                                   ,(LongVId_Overflow, VId_Overflow_tag)
                                                   ,(LongVId_Size, VId_Size_tag)
                                                   ,(LongVId_Subscript, VId_Subscript_tag)
                                                   ,(LongVId_Fail, VId_Fail_tag)
                                                   ]
                                     end
                       }
fun mergeEnv(env1 : Env, env2 : Env)
    = { equalityForTyVarMap = USyntax.TyVarMap.unionWith #2 (#equalityForTyVarMap env1, #equalityForTyVarMap env2)
      , equalityForTyNameMap = USyntax.TyNameMap.unionWith #2 (#equalityForTyNameMap env1, #equalityForTyNameMap env2)
      , exnTagMap = USyntax.LongVIdMap.unionWith #2 (#exnTagMap env1, #exnTagMap env2)
      }

fun updateEqualityForTyVarMap(f, env : Env) = { equalityForTyVarMap = f (#equalityForTyVarMap env)
                                              , equalityForTyNameMap = #equalityForTyNameMap env
                                              , exnTagMap = #exnTagMap env
                                              }

fun freshVId(ctx : Context, name: string) = let val n = !(#nextVId ctx)
                                            in #nextVId ctx := n + 1
                                             ; USyntax.MkVId(name, n)
                                            end

local structure U = USyntax
      structure F = FSyntax
      (* toFTy : Context * Env * USyntax.Ty -> FSyntax.Ty *)
      (* toFPat : Context * Env * USyntax.Pat -> unit USyntax.VIdMap.map * FSyntax.Pat *)
      (* toFExp : Context * Env * USyntax.Exp -> FSyntax.Exp *)
      (* toFDecs : Context * Env * USyntax.Dec list -> Env * FSyntax.Dec list *)
      (* getEquality : Context * Env * USyntax.Ty -> FSyntax.Exp *)
      val overloads = let open Typing InitialEnv
                      in List.foldl (fn ((vid, xs), m) => USyntax.VIdMap.insert (m, vid, List.foldl USyntax.TyNameMap.insert' USyntax.TyNameMap.empty xs)) USyntax.VIdMap.empty
                                    [(VId_abs, [(primTyName_int, VId_Int_abs)
                                               ,(primTyName_real, VId_Real_abs)
                                               ]
                                     )
                                    ,(VId_TILDE, [(primTyName_int, VId_Int_TILDE)
                                                 ,(primTyName_word, VId_Word_TILDE)
                                                 ,(primTyName_real, VId_Real_TILDE)
                                                 ]
                                     )
                                    ,(VId_div, [(primTyName_int, VId_Int_div)
                                               ,(primTyName_word, VId_Word_div)
                                               ]
                                     )
                                    ,(VId_mod, [(primTyName_int, VId_Int_mod)
                                               ,(primTyName_word, VId_Word_mod)
                                               ]
                                     )
                                    ,(VId_TIMES, [(primTyName_int, VId_Int_TIMES)
                                                 ,(primTyName_word, VId_Word_TIMES)
                                                 ,(primTyName_real, VId_Real_TIMES)
                                                 ]
                                     )
                                    ,(VId_DIVIDE, [(primTyName_real, VId_Real_DIVIDE)
                                                  ]
                                     )
                                    ,(VId_PLUS, [(primTyName_int, VId_Int_PLUS)
                                                ,(primTyName_word, VId_Word_PLUS)
                                                ,(primTyName_real, VId_Real_PLUS)
                                                ]
                                     )
                                    ,(VId_MINUS, [(primTyName_int, VId_Int_MINUS)
                                                 ,(primTyName_word, VId_Word_MINUS)
                                                 ,(primTyName_real, VId_Real_MINUS)
                                                 ]
                                     )
                                    ,(VId_LT, [(primTyName_int, VId_Int_LT)
                                              ,(primTyName_word, VId_Word_LT)
                                              ,(primTyName_real, VId_Real_LT)
                                              ,(primTyName_string, VId_String_LT)
                                              ,(primTyName_char, VId_Char_LT)
                                              ]
                                     )
                                    ,(VId_LE, [(primTyName_int, VId_Int_LE)
                                              ,(primTyName_word, VId_Word_LE)
                                              ,(primTyName_real, VId_Real_LE)
                                              ,(primTyName_string, VId_String_LE)
                                              ,(primTyName_char, VId_Char_LE)
                                              ]
                                     )
                                    ,(VId_GT, [(primTyName_int, VId_Int_GT)
                                              ,(primTyName_word, VId_Word_GT)
                                              ,(primTyName_real, VId_Real_GT)
                                              ,(primTyName_string, VId_String_GT)
                                              ,(primTyName_char, VId_Char_GT)
                                              ]
                                     )
                                    ,(VId_GE, [(primTyName_int, VId_Int_GE)
                                              ,(primTyName_word, VId_Word_GE)
                                              ,(primTyName_real, VId_Real_GE)
                                              ,(primTyName_string, VId_String_GE)
                                              ,(primTyName_char, VId_Char_GE)
                                              ]
                                     )
                                    ]
                      end
in
fun toFTy(ctx : Context, env : Env, U.TyVar(span, tv)) = F.TyVar tv
  | toFTy(ctx, env, U.RecordType(span, fields)) = let fun doField(label, ty) = (label, toFTy(ctx, env, ty))
                                                  in F.RecordType (List.map doField fields)
                                                  end
  | toFTy(ctx, env, U.TyCon(span, tyargs, longtycon)) = let fun doTy ty = toFTy(ctx, env, ty)
                                                        in F.TyCon(List.map doTy tyargs, longtycon)
                                                        end
  | toFTy(ctx, env, U.FnType(span, paramTy, resultTy)) = let fun doTy ty = toFTy(ctx, env, ty)
                                                         in F.FnType(doTy paramTy, doTy resultTy)
                                                         end
and toFPat(ctx, env, U.WildcardPat span) = (USyntax.VIdMap.empty, F.WildcardPat)
  | toFPat(ctx, env, U.SConPat(span, scon)) = (USyntax.VIdMap.empty, F.SConPat(scon))
  | toFPat(ctx, env, U.VarPat(span, vid, ty)) = (USyntax.VIdMap.empty, F.VarPat(vid, toFTy(ctx, env, ty))) (* TODO *)
  | toFPat(ctx, env, U.RecordPat{sourceSpan=span, fields, wildcard}) = let fun doField(label, pat) = let val (_, pat') = toFPat(ctx, env, pat)
                                                                                                     in (label, pat')
                                                                                                     end
                                                                       in (USyntax.VIdMap.empty, F.RecordPat(List.map doField fields, wildcard)) (* TODO *)
                                                                       end
  | toFPat(ctx, env, U.ConPat { sourceSpan = span, longvid, payload = NONE, tyargs, isSoleConstructor })
    = (USyntax.VIdMap.empty, F.ConPat(LongVIdToPath longvid, NONE, List.map (fn ty => toFTy(ctx, env, ty)) tyargs))
  | toFPat(ctx, env, U.ConPat { sourceSpan = span, longvid, payload = SOME payloadPat, tyargs, isSoleConstructor })
    = let val (m, payloadPat') = toFPat(ctx, env, payloadPat)
      in (USyntax.VIdMap.empty, F.ConPat(LongVIdToPath longvid, SOME payloadPat', List.map (fn ty => toFTy(ctx, env, ty)) tyargs))
      end
  | toFPat(ctx, env, U.TypedPat(_, pat, _)) = toFPat(ctx, env, pat)
  | toFPat(ctx, env, U.LayeredPat(span, vid, ty, innerPat)) = let val (m, innerPat') = toFPat(ctx, env, innerPat)
                                                              in (USyntax.VIdMap.empty, F.LayeredPat(vid, toFTy(ctx, env, ty), innerPat')) (* TODO *)
                                                              end
and toFExp(ctx, env, U.SConExp(span, scon)) = F.SConExp(scon)
  | toFExp(ctx, env, U.VarExp(span, longvid as USyntax.MkShortVId vid, _, [(tyarg, cts)]))
    = if U.eqVId(vid, InitialEnv.VId_EQUAL) then
          getEquality(ctx, env, tyarg)
      else
          (case USyntax.VIdMap.find(overloads, vid) of
               SOME ov => (case tyarg of
                               U.TyCon(_, [], tycon) => (case USyntax.TyNameMap.find (ov, tycon) of
                                                             SOME vid' => F.LongVarExp(vid')
                                                           | NONE => raise Fail ("invalid use of " ^ USyntax.print_VId vid)
                                                        )
                             | _ => raise Fail ("invalid use of " ^ USyntax.print_VId vid)
                          )
             | NONE => if List.exists (fn USyntax.IsEqType _ => true | _ => false) cts then
                           F.AppExp(F.TyAppExp(F.LongVarExp(longvid), toFTy(ctx, env, tyarg)), getEquality(ctx, env, tyarg))
                       else
                           F.TyAppExp(F.LongVarExp(longvid), toFTy(ctx, env, tyarg))
          )
  | toFExp(ctx, env, U.VarExp(span, longvid, _, tyargs))
    = List.foldl (fn ((ty, cts), e) =>
                     if List.exists (fn USyntax.IsEqType _ => true | _ => false) cts then
                         F.AppExp(F.TyAppExp(e, toFTy(ctx, env, ty)), getEquality(ctx, env, ty))
                     else
                         F.TyAppExp(e, toFTy(ctx, env, ty))
                 ) (F.LongVarExp(longvid)) tyargs
  | toFExp(ctx, env, U.RecordExp(span, fields)) = let fun doField (label, e) = (label, toFExp(ctx, env, e))
                                                  in F.RecordExp (List.map doField fields)
                                                  end
  | toFExp(ctx, env, U.LetInExp(span, decs, e))
    = let val (env, decs) = toFDecs(ctx, env, decs)
      in List.foldr F.LetExp (toFExp(ctx, env, e)) decs
      end
  | toFExp(ctx, env, U.AppExp(span, e1, e2)) = F.AppExp(toFExp(ctx, env, e1), toFExp(ctx, env, e2))
  | toFExp(ctx, env, U.TypedExp(span, exp, _)) = toFExp(ctx, env, exp)
  | toFExp(ctx, env, U.IfThenElseExp(span, e1, e2, e3)) = F.IfThenElseExp(toFExp(ctx, env, e1), toFExp(ctx, env, e2), toFExp(ctx, env, e3))
  | toFExp(ctx, env, U.CaseExp(span, e, ty, matches))
    = let fun doMatch(pat, exp) = let val (_, pat') = toFPat(ctx, env, pat)
                                  in (pat', toFExp(ctx, env, exp)) (* TODO: environment *)
                                  end
      in F.CaseExp(span, toFExp(ctx, env, e), toFTy(ctx, env, ty), List.map doMatch matches)
      end
  | toFExp(ctx, env, U.FnExp(span, vid, ty, body))
    = let val env' = env (* TODO *)
      in F.FnExp(vid, toFTy(ctx, env, ty), toFExp(ctx, env', body))
      end
  | toFExp(ctx, env, U.ProjectionExp { sourceSpan = span, label = label, recordTy = recordTy, fieldTy = fieldTy })
    = F.ProjectionExp { label = label, recordTy = toFTy(ctx, env, recordTy), fieldTy = toFTy(ctx, env, fieldTy) }
  | toFExp(ctx, env, U.HandleExp(span, exp, matches))
    = let val exnName = freshVId(ctx, "exn")
          val exnTy = F.TyCon([], Typing.primTyName_exn)
          fun doMatch(pat, exp) = let val (_, pat') = toFPat(ctx, env, pat)
                                  in (pat', toFExp(ctx, env, exp)) (* TODO: environment *)
                                  end
          fun isExhaustive F.WildcardPat = true
            | isExhaustive (F.SConPat _) = false
            | isExhaustive (F.VarPat _) = true
            | isExhaustive (F.RecordPat _) = false (* exn is not a record *)
            | isExhaustive (F.ConPat _) = false (* exn is open *)
            | isExhaustive (F.LayeredPat (_, _, pat)) = isExhaustive pat
          val matches' = List.map doMatch matches
          val matches'' = if List.exists (fn (pat, _) => isExhaustive pat) matches' then
                              matches'
                          else
                              matches' @ [(F.WildcardPat, F.RaiseExp(SourcePos.nullSpan, F.VarExp(exnName)))]
      in F.HandleExp { body = toFExp(ctx, env, exp)
                     , exnName = exnName
                     , handler = F.CaseExp(SourcePos.nullSpan, F.VarExp(exnName), exnTy, matches'')
                     }
      end
  | toFExp(ctx, env, U.RaiseExp(span, exp)) = F.RaiseExp(span, toFExp(ctx, env, exp))
  | toFExp(ctx, env, U.ListExp(span, xs, ty)) = F.ListExp(Vector.map (fn x => toFExp(ctx, env, x)) xs, toFTy(ctx, env, ty))
and doValBind ctx env (U.TupleBind (span, vars, exp)) = F.TupleBind (List.map (fn (vid,ty) => (vid, toFTy(ctx, env, ty))) vars, toFExp(ctx, env, exp))
  | doValBind ctx env (U.PolyVarBind (span, vid, U.TypeScheme(tvs, ty), exp))
    = let val ty0 = toFTy (ctx, env, ty)
          val ty' = List.foldr (fn ((tv,cts),ty1) =>
                                   case cts of
                                       [] => F.ForallType (tv, ty1)
                                     | [U.IsEqType _] => F.ForallType (tv, F.FnType (F.FnType (F.PairType (F.TyVar tv, F.TyVar tv), F.TyCon([], Typing.primTyName_bool)), ty1))
                                     | _ => raise Fail "invalid type constraint"
                               ) ty0 tvs
          fun doExp (env', [])
              = toFExp(ctx, env', exp)
            | doExp (env', (tv,cts) :: rest)
              = (case cts of
                     [] => F.TyAbsExp (tv, doExp (env', rest))
                   | [U.IsEqType _] => let val vid = freshVId(ctx, "eq")
                                           val eqTy = F.FnType (F.PairType (F.TyVar tv, F.TyVar tv), F.TyCon([], Typing.primTyName_bool))
                                           val env'' = updateEqualityForTyVarMap(fn m => USyntax.TyVarMap.insert(m, tv, vid), env')
                                       in F.TyAbsExp (tv, F.FnExp(vid, eqTy, doExp(env'', rest)))
                                       end
                   | _ => raise Fail "invalid type constraint"
                )
      in F.SimpleBind (vid, ty', doExp(env, tvs))
      end
and typeSchemeToTy(ctx, env, USyntax.TypeScheme(vars, ty))
    = let fun go env [] = toFTy(ctx, env, ty)
            | go env ((tv, []) :: xs) = let val env' = env (* TODO *)
                                        in F.ForallType(tv, go env' xs)
                                        end
            | go env ((tv, [U.IsEqType _]) :: xs) = let val env' = env (* TODO *)
                                                        val eqTy = F.FnType(F.PairType(F.TyVar tv, F.TyVar tv), F.TyCon([], Typing.primTyName_bool))
                                                    in F.ForallType(tv, F.FnType(eqTy, go env' xs))
                                                    end
            | go env ((tv, _) :: xs) = raise Fail "invalid type constraint"
      in go env vars
      end
and getEquality(ctx, env, U.TyCon(span, [tyarg], tyname))
    = if U.eqTyName(tyname, Typing.primTyName_ref) then
          F.TyAppExp(F.LongVarExp(InitialEnv.VId_EQUAL_ref), toFTy(ctx, env, tyarg))
      else if U.eqTyName(tyname, Typing.primTyName_array) then
          F.TyAppExp(F.LongVarExp(InitialEnv.VId_EQUAL_array), toFTy(ctx, env, tyarg))
      else
          (case USyntax.TyNameMap.find(#equalityForTyNameMap env, tyname) of
               NONE => raise Fail (USyntax.PrettyPrint.print_TyName tyname ^ " does not admit equality")
             | SOME longvid => F.AppExp(F.TyAppExp(F.LongVarExp(longvid), toFTy(ctx, env, tyarg)), getEquality(ctx, env, tyarg))
          )
  | getEquality (ctx, env, U.TyCon(span, tyargs, tyname)) = (case USyntax.TyNameMap.find(#equalityForTyNameMap env, tyname) of
                                                                 NONE => raise Fail (USyntax.PrettyPrint.print_TyName tyname ^ " does not admit equality")
                                                               | SOME longvid => let val typesApplied = List.foldl (fn (tyarg, exp) => F.TyAppExp(exp, toFTy(ctx, env, tyarg))) (F.LongVarExp(longvid)) tyargs
                                                                                 in List.foldl (fn (tyarg, exp) => F.AppExp(exp, getEquality(ctx, env, tyarg))) typesApplied tyargs
                                                                                 end
                                                            )
  | getEquality (ctx, env, U.TyVar(span, tv)) = (case USyntax.TyVarMap.find(#equalityForTyVarMap env, tv) of
                                                     NONE => raise Fail ("equality for the type variable not found: " ^ USyntax.PrettyPrint.print_TyVar tv)
                                                   | SOME vid => F.VarExp(vid)
                                                )
  | getEquality (ctx, env, U.RecordType(span, fields)) = let fun doField (label, ty) = (label, getEquality(ctx, env, ty))
                                                         in F.RecordEqualityExp (List.map doField fields)
                                                         end
  | getEquality (ctx, env, U.FnType _) = raise Fail "functions are not equatable; this should have been a type error"
and toFDecs(ctx, env, []) = (env, [])
  | toFDecs(ctx, env, U.ValDec(span, valbinds) :: decs)
    = let val dec = List.map (fn valbind => F.ValDec (doValBind ctx env valbind)) valbinds
          val (env, decs) = toFDecs (ctx, env, decs)
      in (env, dec @ decs)
      end
  | toFDecs(ctx, env, U.RecValDec(span, valbinds) :: decs)
    = let val dec = F.RecValDec (List.map (doValBind ctx env) valbinds)
          val (env, decs) = toFDecs (ctx, env, decs)
      in (env, dec :: decs)
      end
  | toFDecs(ctx, env, U.TypeDec(span, typbinds) :: decs) = toFDecs(ctx, env, decs)
  | toFDecs(ctx, env, U.DatatypeDec(span, datbinds) :: decs)
    = let val dec = F.DatatypeDec (List.map (fn datbind => doDatBind(ctx, env, datbind)) datbinds)
          val (env, valbinds) = genEqualitiesForDatatypes(ctx, env, datbinds)
          val (env, decs) = toFDecs(ctx, env, decs)
      in (env, dec :: (if List.null valbinds then decs else F.RecValDec valbinds :: decs))
      end
  | toFDecs(ctx, env as { exnTagMap, ... }, U.ExceptionDec(span, exbinds) :: decs)
    = let val (exnTagMap, exbinds) = List.foldr (fn (U.ExBind(span, vid as USyntax.MkVId(name, _), optTy), (exnTagMap, xs)) =>
                                                    let val tag = freshVId(ctx, name ^ "_tag")
                                                    in ( USyntax.LongVIdMap.insert(exnTagMap, U.MkShortVId(vid), F.Root(tag))
                                                       , F.ExceptionDec { conName = vid
                                                                        , tagName = tag
                                                                        , payloadTy = Option.map (fn ty => toFTy(ctx, env, ty)) optTy
                                                                        } :: xs
                                                       )
                                                    end
                                                | (U.ExReplication(span, vid, longvid, optTy), (exnTagMap, xs)) =>
                                                  (case USyntax.LongVIdMap.find(#exnTagMap env, longvid) of
                                                       SOME tagPath => ( USyntax.LongVIdMap.insert(exnTagMap, U.MkShortVId(vid), tagPath)
                                                                       , F.ExceptionRepDec { conName = vid
                                                                                           , conPath = LongVIdToPath longvid
                                                                                           , tagPath = tagPath
                                                                                           , payloadTy = Option.map (fn ty => toFTy(ctx, env, ty)) optTy
                                                                                           } :: xs
                                                                       )
                                                     | NONE => raise Fail ("exception not found: " ^ USyntax.print_LongVId longvid)
                                                  )
                                                ) (exnTagMap, []) exbinds
          val env = { equalityForTyVarMap = #equalityForTyVarMap env
                    , equalityForTyNameMap = #equalityForTyNameMap env
                    , exnTagMap = exnTagMap
                    }
          val (env, decs) = toFDecs(ctx, env, decs)
      in (env, exbinds @ decs)
      end
  | toFDecs(ctx, env, U.GroupDec(span, decs) :: decs') = let val (env, decs) = toFDecs(ctx, env, decs)
                                                             val (env, decs') = toFDecs(ctx, env, decs')
                                                         in (env, case decs of
                                                                      [] => decs'
                                                                    | [dec] => dec :: decs'
                                                                    | _ => F.GroupDec(NONE, decs) :: decs'
                                                            )
                                                         end
and doDatBind(ctx, env, U.DatBind(span, tyvars, tycon, conbinds, _)) = F.DatBind(tyvars, tycon, List.map (fn conbind => doConBind(ctx, env, conbind)) conbinds)
and doConBind(ctx, env, U.ConBind(span, vid, NONE)) = F.ConBind(vid, NONE)
  | doConBind(ctx, env, U.ConBind(span, vid, SOME ty)) = F.ConBind(vid, SOME (toFTy(ctx, env, ty)))
and genEqualitiesForDatatypes(ctx, env, datbinds) : Env * F.ValBind list
    = let val nameMap = List.foldl (fn (U.DatBind(span, tyvars, tycon as USyntax.MkTyName(name, _), conbinds, true), map) => USyntax.TyNameMap.insert(map, tycon, freshVId(ctx, "EQUAL" ^ name))
                                   | (_, map) => map) USyntax.TyNameMap.empty datbinds
          val env' = { equalityForTyVarMap = #equalityForTyVarMap env
                     , equalityForTyNameMap = USyntax.TyNameMap.unionWith #2 (#equalityForTyNameMap env, USyntax.TyNameMap.map U.MkShortVId nameMap)
                     , exnTagMap = #exnTagMap env
                     }
          fun doDatBind(U.DatBind(span, tyvars, tycon, conbinds, true), valbinds)
              = let val vid = USyntax.TyNameMap.lookup(nameMap, tycon)
                    fun eqTy t = F.FnType (F.PairType (t, t), F.TyCon([], Typing.primTyName_bool))
                    val tyvars'' = List.map F.TyVar tyvars
                    val ty = List.foldr (fn (tv, ty) => F.FnType(eqTy (F.TyVar tv), ty)) (eqTy (F.TyCon(tyvars'', tycon))) tyvars
                    val ty = List.foldr F.ForallType ty tyvars
                    val tyvars' = List.map (fn tv => (tv, freshVId(ctx, "eq"))) tyvars
                    val eqForTyVars = List.foldl USyntax.TyVarMap.insert' USyntax.TyVarMap.empty tyvars'
                    val env'' = { equalityForTyVarMap = USyntax.TyVarMap.unionWith #2 (#equalityForTyVarMap env', eqForTyVars)
                                , equalityForTyNameMap = #equalityForTyNameMap env'
                                , exnTagMap = #exnTagMap env'
                                }
                    val body = let val param = freshVId(ctx, "p")
                                   val paramTy = let val ty = F.TyCon(tyvars'', tycon)
                                                 in F.PairType(ty, ty)
                                                 end
                               in F.FnExp ( param
                                          , paramTy
                                          , F.CaseExp ( SourcePos.nullSpan
                                                      , F.VarExp(param)
                                                      , paramTy
                                                      , List.foldr (fn (U.ConBind (span, conName, NONE), rest) =>
                                                                       let val conPat = F.ConPat(F.Root(conName), NONE, tyvars'')
                                                                       in ( F.TuplePat [conPat, conPat]
                                                                          , F.VarExp(InitialEnv.VId_true)
                                                                          ) :: rest
                                                                       end
                                                                   | (U.ConBind (span, conName, SOME payloadTy), rest) =>
                                                                     let val payload1 = freshVId(ctx, "a")
                                                                         val payload2 = freshVId(ctx, "b")
                                                                         val payloadEq = getEquality(ctx, env'', payloadTy)
                                                                         val payloadTy = toFTy(ctx, env, payloadTy)
                                                                     in ( F.TuplePat [F.ConPat(F.Root(conName), SOME (F.VarPat(payload1, payloadTy)), tyvars''), F.ConPat(F.Root(conName), SOME (F.VarPat(payload2, payloadTy)), tyvars'')]
                                                                        , F.AppExp(payloadEq, F.TupleExp [F.VarExp(payload1), F.VarExp(payload2)])
                                                                        ) :: rest
                                                                     end
                                                                   )
                                                                   [(F.WildcardPat, F.VarExp(InitialEnv.VId_false))]
                                                                   conbinds
                                                      )
                                          )
                               end
                    val body = List.foldr (fn ((tv, eqParam), ty) => let val paramTy = eqTy (F.TyVar tv)
                                                                     in F.FnExp ( eqParam
                                                                                , paramTy
                                                                                , body
                                                                                )
                                                                     end) body tyvars'
                    val body = List.foldr F.TyAbsExp body tyvars
                in F.SimpleBind (vid, ty, body) :: valbinds
                end
            | doDatBind(_, valbinds) = valbinds
      in (env', List.foldr doDatBind [] datbinds)
      end
fun signatureToTy(ctx, env, { valMap, tyConMap, strMap } : U.Signature)
    = let val exnTags = Syntax.VIdMap.foldli (fn (vid, (tysc, ids), set) => if ids = Syntax.ExceptionConstructor then
                                                                                Syntax.VIdSet.add(set, vid)
                                                                            else
                                                                                set
                                             ) Syntax.VIdSet.empty valMap
      in F.SigType { valMap = Syntax.VIdMap.map (fn (tysc, ids) => typeSchemeToTy(ctx, env, tysc)) valMap
                   , strMap = Syntax.StrIdMap.map (fn U.MkSignature s => signatureToTy(ctx, env, s)) strMap
                   , exnTags = exnTags
                   , equalityMap = Syntax.TyConMap.mapPartial (fn _ => NONE
                                                               (* { typeFunction = U.TypeFunction(tyvars, ty), admitsEquality = true, ... } =>
                                                                  let fun eqTy ty = F.FnType (F.PairType (ty, ty), F.TyCon ([], Typing.primTyName_bool))
                                                                      val ty = toFTy(ctx, env, ty)
                                                                      val ty = List.foldr (fn (tv, ty) => F.FnType (eqTy (F.TyVar tv), ty)) (eqTy ty) tyvars
                                                                  in SOME (List.foldr F.ForallType ty tyvars)
                                                                  end
                                                              | { admitsEquality = false, ... } => NONE (* TODO: ref and array *)
*)
                                                              ) tyConMap
                   } (* TODO: pack existentials *)
      end
fun strExpToFExp(ctx, env : Env, U.StructExp { sourceSpan, valMap, tyConMap, strMap })
    = let val equalities = Syntax.TyConMap.foldli (fn (_, _, xs) => xs
                                                  (* (tycon, { typeFunction = U.TypeFunction(tyvars, ty), admitsEquality = true, ... }, xs) =>
                                                      let fun eqTy ty = F.FnType (F.PairType (ty, ty), F.TyCon ([], Typing.primTyName_bool))
                                                          val tyvars' = List.map (fn tv => (tv, freshVId(ctx, "eq"))) tyvars
                                                          val env' = { equalityForTyVarMap = List.foldl USyntax.TyVarMap.insert' (#equalityForTyVarMap env) tyvars'
                                                                     , equalityForTyNameMap = #equalityForTyNameMap env
                                                                     , exnTagMap = #exnTagMap env
                                                                     }
                                                          val body = getEquality(ctx, env', ty)
                                                          val body = List.foldr (fn ((tv, eqParam), body) => F.FnExp (eqParam, eqTy (F.TyVar tv), body)) body tyvars'
                                                          val body = List.foldr F.TyAbsExp body tyvars
                                                          val ty = List.foldl (fn (tv, ty) => F.FnType(eqTy (F.TyVar tv), ty)) (toFTy(ctx, env, ty)) tyvars
                                                          val ty = List.foldr F.ForallType ty tyvars
                                                          val vid = freshVId(ctx, "eq")
                                                      in (tycon, vid, body, ty) :: xs
                                                      end
                                                  | (_, { admitsEquality = false, ... }, xs) => xs
*)
                                                  ) [] tyConMap
          val exp = F.StructExp { valMap = Syntax.VIdMap.map (fn (longvid, ids) => LongVIdToPath(longvid)) valMap
                                , strMap = Syntax.StrIdMap.map LongStrIdToPath strMap
                                , exnTagMap = Syntax.VIdMap.mapPartial (fn (longvid, ids) => if ids = Syntax.ExceptionConstructor then
                                                                                                 case USyntax.LongVIdMap.find (#exnTagMap env, longvid) of
                                                                                                     SOME path => SOME path
                                                                                                   | NONE => raise Fail ("exception tag not found for " ^ USyntax.print_LongVId longvid)
                                                                                             else
                                                                                                 NONE
                                                                       ) valMap
                                , equalityMap = List.foldl (fn ((tycon, vid, _, _), m) => Syntax.TyConMap.insert(m, tycon, F.Root vid)) Syntax.TyConMap.empty equalities
                                }
      in (env, List.foldl (fn ((_, vid, fnBody, ty), exp) => F.LetExp(F.ValDec(F.SimpleBind(vid, ty, fnBody)), exp)) exp equalities)
      end
  | strExpToFExp(ctx, env, U.StrIdExp(span, longstrid)) = (env, LongStrIdExp longstrid)
  | strExpToFExp(ctx, env, U.LetInStrExp(span, strdecs, strexp)) = let val (env', decs) = strDecsToFDecs(ctx, env, strdecs)
                                                                       val (env', exp) = strExpToFExp(ctx, env', strexp)
                                                                   in (env', List.foldr F.LetExp exp decs)
                                                                   end
and strDecToFDecs(ctx, env : Env, U.CoreDec(span, dec)) = toFDecs(ctx, env, [dec])
  | strDecToFDecs(ctx, env, U.StrBindDec(span, strid, strexp, s))
    = let val vid = F.strIdToVId strid
          val ty = signatureToTy(ctx, env, s)
          val (env', exp) = strExpToFExp(ctx, env, strexp)
          fun updateExnTagMap (strids, { valMap, strMap, ... }, path, exnTagMap)
              = let val exnTagMap = Syntax.VIdMap.foldli (fn (vid, (tysc, Syntax.ExceptionConstructor), m) => USyntax.LongVIdMap.insert(m, U.MkLongVId(strid, strids, vid), F.Child(path, F.ExnTagLabel vid))
                                                         | (_, (_, _), m) => m
                                                         ) exnTagMap valMap
                in Syntax.StrIdMap.foldli (fn (strid, U.MkSignature s, m) => updateExnTagMap(strids @ [strid], s, F.Child(path, F.StructLabel strid), m)) exnTagMap strMap
                end
          val env'' = { equalityForTyVarMap = #equalityForTyVarMap env
                      , equalityForTyNameMap = USyntax.TyNameMap.unionWith #2 (#equalityForTyNameMap env, #equalityForTyNameMap env')
                      , exnTagMap = updateExnTagMap ([], s, F.Root vid, #exnTagMap env)
                      }
      in (env'', [F.ValDec(F.SimpleBind(vid, ty, exp))]) (* TODO: unpack existentials *)
      end
  | strDecToFDecs(ctx, env, U.GroupStrDec(span, decs)) = let val (env, decs) = strDecsToFDecs(ctx, env, decs)
                                                         in (env, case decs of
                                                                      [] => decs
                                                                    | [_] => decs
                                                                    | _ => [F.GroupDec(NONE, decs)]
                                                            )
                                                         end
and strDecsToFDecs(ctx, env : Env, []) = (env, [])
  | strDecsToFDecs(ctx, env, dec :: decs) = let val (env, dec) = strDecToFDecs(ctx, env, dec)
                                                val (env, decs) = strDecsToFDecs(ctx, env, decs)
                                            in (env, dec @ decs)
                                            end
fun programToFDecs(ctx, env : Env, []) = (env, [])
  | programToFDecs(ctx, env, USyntax.StrDec dec :: topdecs) = let val (env, decs) = strDecToFDecs(ctx, env, dec)
                                                                  val (env, decs') = programToFDecs(ctx, env, topdecs)
                                                              in (env, decs @ decs')
                                                              end
fun isAlphaNumName name = List.all (fn c => Char.isAlphaNum c orelse c = #"_") (String.explode name)
fun libraryToFDecs(ctx, tenv: Typing.Env, env, decs)
    = case (Syntax.VIdMap.find (#valMap tenv, Syntax.MkVId "export"), Syntax.StrIdMap.find (#strMap tenv, Syntax.MkStrId "export")) of
          (NONE, NONE) => raise Fail "No value to export was found."
        | (SOME (_, _, longvid), NONE) => let val (env, decs) = programToFDecs(ctx, env, decs)
                                   in (env, decs @ [ F.ExportValue (F.LongVarExp longvid) ])
                                   end
        | (NONE, SOME ({ valMap, ... }, U.MkLongStrId(strid0, strids))) =>
          let val fields = Syntax.VIdMap.listItems (Syntax.VIdMap.mapPartiali (fn (vid, _) => let val name = Syntax.getVIdName vid
                                                                                              in if isAlphaNumName name then
                                                                                                     SOME (name, F.LongVarExp(U.MkLongVId(strid0, strids, vid)))
                                                                                                 else if String.isSuffix "'" name then
                                                                                                     let val name' = String.substring (name, 0, String.size name - 1)
                                                                                                     in if isAlphaNumName name' andalso not (Syntax.VIdMap.inDomain (valMap, Syntax.MkVId name')) then
                                                                                                            SOME (name', F.LongVarExp(U.MkLongVId(strid0, strids, vid)))
                                                                                                        else
                                                                                                            NONE
                                                                                                     end
                                                                                                 else
                                                                                                     NONE
                                                                                              end
                                                                              ) valMap)
              val (env, decs) = programToFDecs(ctx, env, decs)
          in (env, decs @ [ F.ExportModule (Vector.fromList fields) ])
          end
        | (SOME _, SOME _) => raise Fail "The value to export is ambiguous."
end (* local *)
end (* structure ToFSyntax *)
