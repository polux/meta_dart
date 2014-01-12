// Copyright (c) 2014, Google Inc. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

// Author: Paul Brauner (polux@google.com)

library parser;

import 'package:persistent/persistent.dart';
import 'package:meta_dart/datatypes.dart';
import 'package:parsers/parsers.dart';
import 'package:collection/equality.dart';

final _LIST_EQUALITY = const ListEquality(const DefaultEquality());

_singleton(key, val) => new PersistentMap().insert(key, val);
_union(List ms) => ms.fold(new PersistentMap(), (m1, m2) => m1.union(m2));

PersistentMap<String, Clazz> _mkClassEnv(List<Clazz> clazzes) {
  return clazzes.fold(new PersistentMap(),
                      (acc, clazz) => acc.insert(clazz.name, clazz));
}

class SDartParsers extends LanguageParsers {
  SDartParsers() : super(reservedNames: ['class', 'new', 'final', 'this',
                                         'true', 'false', 'run', 'lift',
                                         'return', 'if', 'else', 'operator']);

  get start => prog().between(whiteSpace, eof);

  _params() => parens(identifier.sepBy(comma));
  _args() => parens(rec(expression).sepBy(comma));

  prog() => classDecl().many + mainFun()
          ^ (decls, expr) => new Program(_mkClassEnv(decls), expr);

  classDecl() =>
      reserved['class'] > (identifier >> (id) => braces(classBody(id)));

  classBody(id) => fieldDecl().many >> classBodyEnd(id);

  classBodyEnd(id) => (fields) =>
      (ctorDecl(id, fields) + methodDecl().many)
      ^ (_, methods) => new Clazz(id, fields, _union(methods));

  fieldDecl() => (reserved['final'] + identifier + semi) ^ (_, x, __) => x;

  ctorDecl(className, classFields) {
    final expectedInitializers = classFields.map((f) => "this.$f").join(", ");
    final expected = "'$className($expectedInitializers);'";
    return checkCtorDecl(className, classFields) % expected;
  }

  checkCtorDecl(className, classFields) =>
      identifier >> (constructorName) =>
      parens(ctorArg().sepBy(comma)) >> (initializers) =>
      semi >> (_) {
        final sameConstructor = (className == constructorName);
        final sameFields = _LIST_EQUALITY.equals(classFields, initializers);
        return (sameConstructor && sameFields) ? success(null) : fail;
      };

  ctorArg() => (reserved['this'] + dot + identifier) ^ (_, __, id) => id;

  // we left factorize function name and params for efficiency
  methodDecl() => methodPrefix() >> methodSuffix;

  methodPrefix() => (reserved['operator'] > operator) | identifier;

  operatorDecl() => reserved['operator'] + operator + _params();

  get operator => choice(
      ["||", "&&", "==", "<=", "<", ">=", ">", "+", "-", "*", "/", "~/", "%"]
      .map(symbol).toList());

  methodSuffix(name) => _params() >> (params) => methodBody(name, params);

  methodBody(name, params) => shortMethodDecl(name, params)
                            | longMethodDecl(name, params);

  shortMethodDecl(name, params) =>
      symbol("=>") + expression() + semi
      ^ (_, body, __) => _singleton(name, new Method(params, body));

  longMethodDecl(name, params) =>
      braces(lets())
      ^ (body) => _singleton(name, new Method(params, body));

  lets() => rec(let) | rec(ifs);

  let() => reserved['final'] + identifier + symbol('=')
             + expression() + semi + rec(lets)
         ^ (_, id, __, expr, ___, tail) => new Let(id, expr, tail);

  ifs() => rec(longIf) | rec(returnExpr);

  longIf() => reserved['if'] + parens(rec(expression)) + braces(rec(lets))
                + reserved['else'] + braces(rec(lets))
            ^ (_, cond, thenE, __, elseE) => new IfThenElse(cond, thenE, elseE);

  returnExpr() => reserved['return'] + expression() + semi
                ^ (_, expr, __) => expr;

  expression() => rec(ifThenElse);


  funCalls(prefix) => (funCall(prefix) >> funCalls)
                    | success(prefix);

  funCall(fun) => rec(_args) ^ (arguments) => new FunctionCall(fun, arguments);

  sends(receiver) => (dot > sendOrGetSend(receiver) >> funCalls >> sends)
                   | success(receiver);

  sendsTail(expr) => sends(expr) | success(expr);

  sendOrGetSend(receiver) => send(receiver) | getSend(receiver);

  send(receiver) => identifier + rec(_args)
                  ^ (id, arguments) => new Send(receiver, id, arguments);

  getSend(receiver) => identifier ^ (id) => new GetSend(receiver, id);

  self() => reserved['this'] ^ (_) => new Self();

  variable() => identifier ^ (x) => new Variable(x);

  ctorCall() => reserved['new'] + identifier + rec(_args)
              ^ (_, id, arguments) => new ConstructorCall(id, arguments);

  lambda() => shortLambda() | longLambda();

  shortLambda() => _params() + symbol("=>") + rec(expression)
                 ^ (parameters, _, body) => new Lambda(parameters, body);

  longLambda() => _params() + braces(lets())
                ^ (parameters, body) => new Lambda(parameters, body);

  // we left-factorize orExpression for efficiency
  ifThenElse() => rec(orExpression) >> thenElse;

  thenElse(cond) {
    final ifE = rec(ifThenElse);
    mkIf(_, thenE, __, elseE) => new IfThenElse(cond, thenE, elseE);
    return symbol("?") + ifE + symbol(":") + ifE ^ mkIf
         | success(cond);
  }

  _binOp(str) => symbol(str) > success((x, y) => new Send(x, str, [y]));
  _negOp() => symbol("!=") > success((x, y) =>
      new Send(new Send(x, "==", [y]), "!", []));

  orExpression() => andExpression().chainl1(_binOp("||"));

  andExpression() => equalityExpression().chainl1(_binOp("&&"));

  equalityExpression() => relationalExpression().chainl1(
      _binOp("==") | _negOp());

  relationalExpression() => additiveExpression().chainl1(
      _binOp(">") | _binOp(">=") | _binOp("<") | _binOp("<="));

  additiveExpression() => multiplicativeExpression().chainl1(
      _binOp("+") | _binOp("-"));

  multiplicativeExpression() => unaryExpression().chainl1(
      _binOp("*") | _binOp("/") | _binOp("%") | _binOp("~/"));

  unaryExpression() => rec(negExpression)
                     | rec(escape)
                     | rec(postFixExpression);

  negExpression() => (symbol('!') > rec(postFixExpression))
      ^ (e) => new IfThenElse(e, new BoolLit(false), new BoolLit(true));

  escape() => (symbol('~') > rec(postFixExpression)) ^ (e) => new Escape(e);

  postFixExpression() => rec(atom) >> funCalls >> sends;

  atom() => rec(self)
          | rec(lambda)
          | rec(variable)
          | rec(ctorCall)
          | rec(numLit)
          | rec(boolLit)
          | rec(stringLit)
          | rec(quote)
          | rec(run)
          | rec(lift)
          | parens(rec(expression));

  numLit() => (floatLiteral | intLiteral) ^ (n) => new NumLit(n);

  boolLit() => (reserved['true'] ^ (_) => new BoolLit(true))
             | (reserved['false'] ^ (_) => new BoolLit(false));

  stringLit() => stringLiteral ^ (str) => new StringLit(str);

  quote() => angles(rec(expression)) ^ (e) => new Brackets(e);

  run() => (reserved['run'] > parens(rec(expression))) ^ (e) => new Run(e);

  lift() => (reserved['lift'] > parens(rec(expression))) ^ (e) => new Lift(e);

  mainFun() => symbol('main') + parens(whiteSpace) + braces(letPrints())
             ^ (_, __, e) => e;

  letPrints() => rec(letPrint) | printStatements();

  letPrint() => (reserved['final'] + identifier + symbol('=')
                  + expression() + semi + rec(letPrints))
              ^ (_, id, __, expr, ___, tail) => new LetPrint(id, expr, tail);

  printStatements() => printStatement().many ^ (es) => new Print(es);

  printStatement() => symbol('print') + parens(expression()) + semi
                    ^ (_, e, __) => e;
}
