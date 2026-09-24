import Foundation

/// Spoken numbers: digits ("12") or small words ("twelve", "a").
enum SpokenNumber {
    static let words: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
        "thirty": 30, "forty": 40, "forty five": 45, "fifty": 50, "sixty": 60, "ninety": 90,
        "hundred": 100, "a hundred": 100, "half": 0.5, "couple": 2, "a couple": 2, "few": 3, "a few": 3
    ]

    static func value(_ word: String) -> Double? {
        if let n = Double(word.replacingOccurrences(of: ",", with: "")) { return n }
        return words[word]
    }
}

/// "5 minutes", "an hour and a half", "1 hour 30 minutes", "half an hour", "90 seconds".
public enum SpokenDuration {
    static let units: [String: Int] = [
        "second": 1, "seconds": 1, "sec": 1, "secs": 1,
        "minute": 60, "minutes": 60, "min": 60, "mins": 60,
        "hour": 3600, "hours": 3600, "hr": 3600, "hrs": 3600
    ]

    /// Parses a duration starting at `start`. Returns seconds and the index after it.
    static func parse(_ tokens: [Token], from start: Int) -> (seconds: Int, end: Int)? {
        var i = start
        var total = 0.0
        var lastUnit = 0
        var matched = false

        while i < tokens.count {
            // "half an hour", "half a minute"
            if tokens[i].norm == "half", i + 2 < tokens.count, ["an", "a"].contains(tokens[i + 1].norm),
               let unit = units[tokens[i + 2].norm] {
                total += 0.5 * Double(unit)
                lastUnit = unit
                i += 3
                matched = true
                continue
            }
            // "and a half" after a unit
            if matched, tokens[i].norm == "and", i + 2 < tokens.count,
               tokens[i + 1].norm == "a", tokens[i + 2].norm == "half", lastUnit > 0 {
                total += 0.5 * Double(lastUnit)
                i += 3
                continue
            }
            var j = i
            if matched, tokens[j].norm == "and" { j += 1 }
            guard j < tokens.count, var n = SpokenNumber.value(tokens[j].norm) else { break }
            var k = j + 1
            // Two-word amounts: "a couple", "a few"
            if ["a", "an"].contains(tokens[j].norm), k < tokens.count,
               let pair = SpokenNumber.words["a " + tokens[k].norm] {
                n = pair
                k += 1
            }
            // "a couple of minutes", "a few minutes"
            if k < tokens.count, tokens[k].norm == "of" { k += 1 }
            guard k < tokens.count, let unit = units[tokens[k].norm] else { break }
            total += n * Double(unit)
            lastUnit = unit
            i = k + 1
            matched = true
        }
        guard matched, total >= 1 else { return nil }
        return (Int(total.rounded()), i)
    }

    /// Whole-string convenience for tests and callers with plain text.
    public static func seconds(in text: String) -> Int? {
        let tokens = Tokenizer.tokenize(text)
        guard let result = parse(tokens, from: 0), result.end == tokens.count else { return nil }
        return result.seconds
    }

    /// 90 -> "1 minute 30 seconds"
    public static func describe(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
        if m > 0 { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
        if s > 0 || parts.isEmpty { parts.append("\(s) second\(s == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
    }
}

/// Tiny calculator for "what's 12 times 8" / "15 percent of 80" / "square root of 144".
/// Numbers and + − × ÷ with normal precedence. Returns nil for anything else.
public enum SpokenMath {
    public static func evaluate(_ spoken: String) -> Double? {
        var text = " " + spoken.lowercased() + " "
        let symbols: [(String, String)] = [
            ("×", " times "), ("*", " times "), ("÷", " divided by "), ("/", " divided by "),
            ("+", " plus "), ("−", " minus "), ("%", " percent "), ("?", " "), ("=", " ")
        ]
        for (a, b) in symbols { text = text.replacingOccurrences(of: a, with: b) }
        // "-" only as an operator between spaces; keep "-5" as a negative number.
        text = text.replacingOccurrences(of: " - ", with: " minus ")

        var words = text.split(separator: " ").map(String.init)
        // Drop polite lead-ins and the trailing "equal"/"equals".
        let filler: Set<String> = ["what's", "what\u{2019}s", "whats", "what", "is", "calculate", "compute", "how", "much",
                                   "equals", "equal", "the", "answer", "to", "please", "of", "by"]
        let keepOf = words.contains("percent") || words.contains("root")
        words = words.filter { word in
            if word == "of" { return keepOf }
            return !filler.contains(word)
        }

        var numbers: [Double] = []
        var ops: [String] = []
        var i = 0
        func number(at index: inout Int) -> Double? {
            guard index < words.count else { return nil }
            if words[index] == "square", index + 1 < words.count, words[index + 1] == "root" {
                index += 2
                if index < words.count, words[index] == "of" { index += 1 }
                guard let n = number(at: &index), n >= 0 else { return nil }
                return n.squareRoot()
            }
            guard var n = SpokenNumber.value(words[index]) else { return nil }
            index += 1
            if index < words.count, words[index] == "squared" { n *= n; index += 1 }
            if index < words.count, words[index] == "percent" {
                index += 1
                if index < words.count, words[index] == "of" {
                    index += 1
                    guard let base = number(at: &index) else { return nil }
                    return n / 100 * base
                }
                return n / 100
            }
            return n
        }

        guard let first = number(at: &i) else { return nil }
        numbers.append(first)
        let opWords: [String: String] = [
            "plus": "+", "add": "+", "minus": "-", "less": "-", "times": "*", "x": "*",
            "multiplied": "*", "divided": "/", "over": "/"
        ]
        while i < words.count {
            guard let op = opWords[words[i]] else { return nil }
            i += 1
            guard let n = number(at: &i) else { return nil }
            ops.append(op)
            numbers.append(n)
        }
        guard !ops.isEmpty || words.contains("root") || words.contains("percent") || words.contains("squared")
        else { return nil }

        // × and ÷ first, then + and −.
        var nums = [numbers[0]]
        var addOps: [String] = []
        for (index, op) in ops.enumerated() {
            let n = numbers[index + 1]
            switch op {
            case "*": nums[nums.count - 1] *= n
            case "/":
                guard n != 0 else { return nil }
                nums[nums.count - 1] /= n
            default:
                addOps.append(op)
                nums.append(n)
            }
        }
        var result = nums[0]
        for (index, op) in addOps.enumerated() {
            result = op == "+" ? result + nums[index + 1] : result - nums[index + 1]
        }
        return result.isFinite ? result : nil
    }

    public static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

/// Turns `pmset -g batt` output into a sentence.
public enum BatteryReport {
    public static func describe(_ pmset: String) -> String {
        guard let percentRange = pmset.range(of: #"\d{1,3}%"#, options: .regularExpression) else {
            return "This Mac doesn't report a battery."
        }
        let percent = pmset[percentRange]
        let lower = pmset.lowercased()
        if lower.contains("charged") || lower.contains("finishing charge") {
            return "Battery is at \(percent), fully charged."
        }
        if lower.contains("discharging") {
            if let t = lower.range(of: #"\d+:\d{2} remaining"#, options: .regularExpression) {
                let parts = lower[t].split(separator: " ")[0].split(separator: ":")
                if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), h + m > 0 {
                    return "Battery is at \(percent), about \(SpokenDuration.describe(h * 3600 + m * 60)) left."
                }
            }
            return "Battery is at \(percent)."
        }
        if lower.contains("charging") || lower.contains("ac power") {
            return "Battery is at \(percent) and charging."
        }
        return "Battery is at \(percent)."
    }
}
