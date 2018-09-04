copy
MCBase.OBJ
modula.new.OBJ/noquery/replace/continue
MCInit.OBJ
C19.Init.new.OBJ/noquery/replace/continue
MCP1Main.OBJ
C19.Pass1.new.OBJ/noquery/replace/continue
MCP2Main.OBJ
C19.Pass2.new.OBJ/noquery/replace/continue
MCP3Main.OBJ
C19.Pass3.new.OBJ/noquery/replace/continue
MCP4Main.OBJ
C19.Pass4.new.OBJ/noquery/replace/continue
MCSymFile.OBJ
C19.Symfile.new.OBJ/noquery/replace/continue
MCLister.OBJ
C19.Lister.new.OBJ/noquery/replace/terminate
link
modula.new.OBJ
link
C19.Init.new.OBJ/q
 y y y
link
C19.Pass1.new.OBJ/q
 y y y y y y y
link
C19.Pass2.new.OBJ/q
 y y y y
link
C19.Pass3.new.OBJ/q
 y y y
link
C19.Pass4.new.OBJ/q
 y y y y y y
link
C19.Symfile.new.OBJ/q
 y y
link
C19.Lister.new.OBJ/q
 y
