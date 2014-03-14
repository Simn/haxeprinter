import haxe.macro.Expr;
import haxe.macro.Context;
using StringTools;
using haxe.macro.Tools;

class TestFileMacro {
	macro static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var dir = "unit/files";
		for (file in sys.FileSystem.readDirectory(dir)) {
			var path = haxe.io.Path.join([dir, file]);
			fields.push(handleFile(path));
		}
		return fields;
	}
	
	static function handleFile(file:String) {
		var content = sys.io.File.getContent(file);
		content = content.replace("\r", "");
		var r = ~/#test(\(.*?\))?/g;
		
		var el = [];
		el.push(macro var config = Reflect.copy(defaultConfig));
		
		function mkFileEq(s:String) {
			return macro fileEq(original, config, $v{(s.trim() : String)});
		}
		
		var first = true;
		var totalPos = 0;
		while (r.match(content)) {
			var pos = r.matchedPos();
			var p = Context.makePosition({min:totalPos + pos.pos, max:totalPos + pos.pos + pos.len, file: file});
			if (first) {
				first = false;
				el.push(macro var original = $v{(r.matchedLeft().trim() : String)});
			} else {
				el.push(mkFileEq(r.matchedLeft()));
			}
			var matched = r.matched(1);
			if (matched != null) {
				var matched = matched.substr(1, matched.length - 2);
				var split = matched.split("=");
				if (split.length != 2) {
					Context.error("Expected `configField = expr`", p);
				}
				var fieldName = split[0].trim();
				var value = Context.parse(split[1], p);
				el.push(macro config.$fieldName = $value);
			}
			totalPos += pos.pos + pos.len;
			content = r.matchedRight();
		}
		el.push(mkFileEq(content));
		
		var e = macro $b{el};
		
		var fieldName = "test" +(new haxe.io.Path(file).file);
		
		var field = (macro class X {
			function $fieldName() {
				$e;
			}
		}).fields[0];
		return field;
	}
	
	macro static public function test(eSubjects:ExprOf<Array<String>>, el:Array<Expr>) {
		var subjects = switch (eSubjects.expr) {
			case EArrayDecl(el): el;
			case _: [eSubjects];
		}
		var ret = [];
		el.unshift(eSubjects);
		for (e in el) {
			switch (e) {
				case macro $a{el}:
					if (el.length != subjects.length) {
						Context.error("Invalid array length, should be " +subjects.length, e.pos);
					}
					for (i in 0...subjects.length) {
						ret.push(macro exprEq($e{subjects[i]}, $e{el[i]}));
					}
				case macro $lhs = $rhs:
					var sLhs = lhs.toString().split(".");
					sLhs.unshift("currentConfig");
					ret.push(macro $p{sLhs} = $rhs);
				case _:
					ret.push(macro exprEq($e{subjects[0]}, $e));
			}
		}
		var e = macro $b{ret};
		return e;
	}
}