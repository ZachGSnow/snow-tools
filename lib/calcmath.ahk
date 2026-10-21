; ===== CALC MATH =====
; Recursive-descent evaluator for + - * / ( ) and decimals (no eval, no variables).

CalcMathEval(expr) {
    expr := RegExReplace(expr, "\s+")
    if (expr = "")
        throw Error("Empty expression")
    if RegExMatch(expr, "[^0-9+\-*/().]")
        throw Error("Invalid characters in expression")
    pos := 1
    result := CalcParseExpr(expr, &pos)
    if (pos <= StrLen(expr))
        throw Error("Unexpected character in expression")
    return result
}

CalcParseExpr(expr, &pos) {
    val := CalcParseTerm(expr, &pos)
    Loop {
        c := (pos <= StrLen(expr)) ? SubStr(expr, pos, 1) : ""
        if (c = "+") {
            pos++
            val += CalcParseTerm(expr, &pos)
        } else if (c = "-") {
            pos++
            val -= CalcParseTerm(expr, &pos)
        } else
            break
    }
    return val
}

CalcParseTerm(expr, &pos) {
    val := CalcParseFactor(expr, &pos)
    Loop {
        c := (pos <= StrLen(expr)) ? SubStr(expr, pos, 1) : ""
        if (c = "*") {
            pos++
            val *= CalcParseFactor(expr, &pos)
        } else if (c = "/") {
            pos++
            divisor := CalcParseFactor(expr, &pos)
            if (divisor = 0)
                throw Error("Division by zero")
            val /= divisor
        } else
            break
    }
    return val
}

CalcParseFactor(expr, &pos) {
    c := (pos <= StrLen(expr)) ? SubStr(expr, pos, 1) : ""
    if (c = "-") {
        pos++
        return -CalcParseFactor(expr, &pos)
    }
    if (c = "+") {
        pos++
        return CalcParseFactor(expr, &pos)
    }
    if (c = "(") {
        pos++
        val := CalcParseExpr(expr, &pos)
        c := (pos <= StrLen(expr)) ? SubStr(expr, pos, 1) : ""
        if (c != ")")
            throw Error("Missing closing parenthesis")
        pos++
        return val
    }
    start := pos
    while (pos <= StrLen(expr) && (CalcIsDigit(SubStr(expr, pos, 1)) || SubStr(expr, pos, 1) = "."))
        pos++
    if (pos = start)
        throw Error("Expected a number")
    return Number(SubStr(expr, start, pos - start))
}

CalcIsDigit(c) {
    return RegExMatch(c, "^\d$") > 0
}

CalcFormatResult(n) {
    if (Abs(n - Round(n)) < 0.000001)
        return Round(n) ""
    s := Format("{:.4f}", n)
    s := RTrim(s, "0")
    s := RTrim(s, ".")
    return s
}
