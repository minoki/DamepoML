signature S = sig
    type t
    type u
    sharing type t = u
end;
structure S : S = struct
type t = int
type u = string
end;
