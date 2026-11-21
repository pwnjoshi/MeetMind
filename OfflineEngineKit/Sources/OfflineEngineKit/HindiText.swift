import Foundation

/// One whitespace-delimited word of a Hindi, Hinglish or English sentence.
struct HindiToken {
    /// The word as written, without surrounding punctuation.
    let raw: String
    /// Canonical lowercase key. Known Devanagari words map to their Latin/English key.
    let key: String
    /// English display form when known, otherwise the raw word.
    let display: String
    let isDevanagari: Bool
    /// True when a Devanagari word was found in the lexicon.
    let isKnown: Bool
    let commaAfter: Bool
    let start: String.Index
    let end: String.Index
    /// End of the word including trailing punctuation.
    let chunkEnd: String.Index
}

/// Script-aware helpers for Hindi (Devanagari), romanized Hindi and mixed English speech.
/// Pure and deterministic: no model, no network.
enum HindiText {
    // MARK: - Scalars

    static func isDevanagari(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x0900 && scalar.value <= 0x097F
    }

    static func containsDevanagari(_ text: String) -> Bool {
        for scalar in text.unicodeScalars where isDevanagari(scalar) { return true }
        return false
    }

    /// Removes nukta and joiners, folds chandrabindu into anusvara and Devanagari digits into ASCII,
    /// so differently spelled Whisper output compares equal.
    static func normalized(_ value: String) -> String {
        var result = ""
        for scalar in value.decomposedStringWithCanonicalMapping.unicodeScalars {
            let code = scalar.value
            if code == 0x093C || code == 0x200C || code == 0x200D { continue }
            if code == 0x0901 { result += "\u{0902}"; continue }
            if code >= 0x0966 && code <= 0x096F { result += String(code - 0x0966); continue }
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    // MARK: - Lexicon (Devanagari spelling -> English / canonical Latin key)

    /// "devanagari,variant=value". Values are display-ready; keys used for matching are lowercased values.
    private static let lexiconSource: String = """
    मैं,मै=main
    मैंने=maine
    मुझे=mujhe
    मुझसे=mujhse
    मेरे,मेरा,मेरी=mere
    हम=hum
    हमें,हमे,हमको=hamein
    हमारा,हमारी,हमारे=hamara
    तुम=tum
    तुम्हें,तुम्हे,तुमको=tumhe
    तुमसे=tumse
    आप=aap
    आपको=aapko
    तू=tu
    वह,वो=wo
    यह=yah
    ये=ye
    यही,येही=yahi
    वही=wahi
    उस=us
    उसका,उसकी,उसके=uska
    इस=is
    इसका,इसकी,इसके=iska
    उन=un
    को=ko
    का=ka
    की=ki
    के=ke
    से=se
    पर=par
    पे=pe
    में=mein
    तक=tak
    भी=bhi
    ही=hi
    ने=ne
    लिए,लिये=liye
    बारे=baare
    वाला,वाली,वाले=wala
    और=aur
    या=ya
    तो=to
    अब=ab
    फिर=phir
    पहले=pehle
    बाद=baad
    अभी=abhi
    सिर्फ=sirf
    बस=bas
    इतना,इतनी=itna
    कुछ=kuch
    सब=sab
    साथ=saath
    क्या=kya
    कौन=kaun
    कब=kab
    क्यों=kyun
    कैसे=kaise
    कहाँ=kahan
    कितना,कितने,कितनी=kitna
    है=hai
    हैं=hain
    हो=ho
    हूँ=hoon
    था,थी,थे=tha
    होगा,होगी,होंगे=hoga
    हुआ,हुई,हुए=hua
    गया,गई,गए,गयी=gaya
    रहेगा,रहेगी,रहेंगे=rahega
    रहा,रही,रहे=raha
    हाँ,हां,हा=haan
    जी=ji
    ठीक=thik
    अच्छा,अछा=accha
    ज़रूर,जरूर=zaroor
    बिल्कुल,बिलकुल=bilkul
    नहीं,नही=nahi
    ना=na
    सही=sahi
    ओके,ओके.=ok
    हाय=hello
    हैलो,हेलो,हलो=hello
    नमस्ते=namaste
    धन्यवाद,शुक्रिया=thanks
    थैंक,थेंक=thank
    यू=you
    चलो=chalo
    चलते=chalte
    लेकिन,मगर=lekin
    वैसे=waise
    मतलब=matlab
    देखो,देखिए,देखिये=dekho
    सुनो,सुनिए=suno
    क्योंकि=kyonki
    इसलिए=isliye
    अरे=arre
    बहुत=bahut
    काफ़ी,काफी=kaafi
    लगता=lagta
    हिसाब=hisaab
    ख्याल,ख़याल=khayal
    चाहिए,चाहिये=chahiye
    करना=karna
    करनी,करनि=karni
    करने=karne
    कर=kar
    करो=karo
    करें,करे,करिए,करिये=karen
    कीजिए,कीजिये,कीजिएगा=kijiye
    करते=karte
    करेंगे=karenge
    करेगा=karega
    करेगी=karegi
    करूँगा,करूंगा=karunga
    करूँगी,करूंगी=karungi
    करोगे=karoge
    करोगी=karogi
    लेते=lete
    लेंगे=lenge
    लो=lo
    लेना=lena
    ले=le
    लूँगा,लूंगा=lunga
    लूँगी,लूंगी=lungi
    लेगा=lega
    लेगी=legi
    दे=de
    दो=do
    देना=dena
    दीजिए,दीजिये,दीजिएगा=dijiye
    दूँगा,दूंगा=dunga
    दूँगी,दूंगी=dungi
    दोगे=doge
    दोगी=dogi
    देंगे=denge
    देगा=dega
    देगी=degi
    दिया=diya
    किया=kiya
    लिया=liya
    भेज=bhej
    भेजना=bhejna
    भेजो=bhejo
    भेजिए,भेजिये=bhejiye
    भेजेगा=bhejega
    भेजेगी=bhejegi
    भेजेंगे=bhejenge
    भेजूँगा,भेजूंगा=bhejunga
    भेजूँगी,भेजूंगी=bhejungi
    भेजोगे=bhejoge
    भेजोगी=bhejogi
    बना=bana
    बनाना=banana
    बनाओ=banao
    बनाइए,बनाइये=banaiye
    बनाएगा,बनायेगा=banayega
    बनाएगी,बनायेगी=banayegi
    बनाएंगे,बनायेंगे=banayenge
    बनाऊँगा,बनाऊंगा=banaunga
    बनाऊँगी,बनाऊंगी=banaungi
    बनाओगे=banaoge
    बनाओगी=banaogi
    देख=dekh
    देखना=dekhna
    देखेगा=dekhega
    देखेगी=dekhegi
    देखूँगा,देखूंगा=dekhunga
    देखूँगी,देखूंगी=dekhungi
    सकते=sakte
    सकती=sakti
    सकता=sakta
    पाऊँगा,पाऊंगा,पाउंगा=paunga
    पाऊँगी,पाऊंगी,पाउंगी=paungi
    पाएगा,पायेगा=payega
    पाएगी,पायेगी=payegi
    पाओगे,पाओगी=paoge
    पता=pata
    बात=baat
    तैयार,तयार=taiyaar
    शुरू=shuru
    खत्म=khatam
    पूरा=poora
    तय=tay
    फैसला=faisla
    फाइनल,फाईनल,फ़ाइनल=final
    डिसाइड,डिसाईड=decide
    पेंडिंग,पेन्डिंग=pending
    कम=kam
    सस्ता=sasta
    अच्छी=accha
    आज=aaj
    कल=kal
    परसों=parso
    अगले,अगला=agle
    अगली=agli
    हफ्ते,हफ्ता,सप्ताह=hafte
    महीने,महीना=mahine
    सुबह=subah
    शाम=shaam
    रात=raat
    मीटिंग,मीटीँग=meeting
    सोमवार,मंडे=Monday
    मंगलवार,ट्यूसडे,ट्यूजडे=Tuesday
    बुधवार,वेडनेसडे,वेंसडे=Wednesday
    गुरुवार,बृहस्पतिवार,थर्सडे,थर्स्डे=Thursday
    शुक्रवार,फ्राइडे,फ्राईडे,फ्रायडे=Friday
    शनिवार,सैटरडे,सटरडे=Saturday
    रविवार,संडे,सनडे=Sunday
    जनवरी=January
    फरवरी=February
    मार्च=March
    अप्रैल=April
    मई=May
    जून=June
    जुलाई=July
    अगस्त=August
    सितंबर,सितम्बर=September
    अक्टूबर,अक्तूबर=October
    नवंबर,नवम्बर,नवेम्बर=November
    दिसंबर,दिसम्बर=December
    एजेंडा,एजेन्डा,अजेंडा,एजेंडे=agenda
    प्रेजेंटेशन,प्रेजेन्टेशन,प्रेसेंटेशन,प्रजेंटेशन,प्रेज़ेंटेशन=presentation
    बजट=budget
    वेंडर,वेन्डर,वेंडार=vendor
    क्लाइंट,क्लायंट,क्लाईंट,क्लाइन्ट=client
    डिज़ाइन,डिजाइन,डिज़ायन=design
    चेंज,चेन्ज=change
    मार्केटिंग=marketing
    लॉन्च,लांच,लाँच,लॉन्च=launch
    डेट=date
    प्राइस=price
    कॉस्ट,कोस्ट=cost
    रिपोर्ट=report
    टीम=team
    प्लान=plan
    टाइमलाइन=timeline
    डेडलाइन=deadline
    रिव्यू=review
    अपडेट=update
    शेयर=share
    कॉल=call
    बुक=book
    ईमेल=email
    मेल=mail
    डॉक्यूमेंट=document
    इनवॉइस=invoice
    कॉन्ट्रैक्ट=contract
    प्रपोज़ल,प्रपोजल,प्रोपोजल=proposal
    नोट्स=notes
    सेल्स=sales
    फाइनेंस=finance
    प्रोडक्ट=product
    प्रोजेक्ट=project
    रिलीज़,रिलीज=release
    टेस्ट=test
    डेमो=demo
    कन्फर्म=confirm
    चेक=check
    सबमिट=submit
    सेंड=send
    शेड्यूल=schedule
    लेट्स,लेटस=lets
    गो=go
    विद=with
    द=the
    लिस्ट=list
    स्टेटस=status
    फीडबैक=feedback
    पेमेंट=payment
    ऑर्डर=order
    रूम=room
    वेन्यू=venue
    टिकट=ticket
    बग=bug
    फीचर=feature
    इवेंट=event
    ऑफिस=office
    कैंपेन=campaign
    ऐप=app
    वेबसाइट=website
    स्लाइड,स्लाइड्स=slides
    डेक=deck
    शीट=sheet
    कोट=quote
    ड्राफ्ट=draft
    पुणे=Pune
    मुंबई=Mumbai
    दिल्ली=Delhi
    बेंगलुरु,बैंगलोर,बंगलौर=Bengaluru
    चेन्नई=Chennai
    हैदराबाद=Hyderabad
    कोलकाता=Kolkata
    अहमदाबाद=Ahmedabad
    जयपुर=Jaipur
    नोएडा=Noida
    """

    static let lexicon: [String: String] = {
        var map: [String: String] = [:]
        for line in lexiconSource.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            for piece in parts[0].split(separator: ",") {
                let key = normalized(String(piece).trimmingCharacters(in: .whitespacesAndNewlines))
                if !key.isEmpty { map[key] = value }
            }
        }
        return map
    }()

    static func isKnownWord(_ word: String) -> Bool {
        lexicon[normalized(word)] != nil
    }

    static let weekdays: Set<String> = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    static let months: Set<String> = ["january", "february", "march", "april", "may", "june", "july",
                                      "august", "september", "october", "november", "december"]

    // MARK: - Tokenizing

    private static func isTrimmable(_ character: Character) -> Bool {
        character.isPunctuation || character.isSymbol
    }

    static func tokenize(_ text: String) -> [HindiToken] {
        var tokens: [HindiToken] = []
        var index = text.startIndex
        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
            guard index < text.endIndex else { break }
            let chunkStart = index
            while index < text.endIndex, !text[index].isWhitespace { index = text.index(after: index) }
            let chunkEnd = index
            var low = chunkStart
            var high = chunkEnd
            while low < high, isTrimmable(text[low]) { low = text.index(after: low) }
            while high > low {
                let previous = text.index(before: high)
                if isTrimmable(text[previous]) { high = previous } else { break }
            }
            guard low < high else { continue }
            let word = String(text[low..<high])
            let trailing = String(text[high..<chunkEnd])
            let hasDevanagari = containsDevanagari(word)
            var key: String
            var display: String
            var known = false
            if hasDevanagari {
                let folded = normalized(word)
                if let value = lexicon[folded] {
                    key = value.lowercased()
                    display = value
                    known = true
                } else {
                    key = folded
                    display = word
                }
            } else {
                key = word.lowercased().replacingOccurrences(of: "\u{2019}", with: "").replacingOccurrences(of: "'", with: "")
                display = word
            }
            if key.isEmpty { key = word }
            if display.isEmpty { display = word }
            tokens.append(HindiToken(raw: word, key: key, display: display, isDevanagari: hasDevanagari,
                                     isKnown: known, commaAfter: trailing.contains(","),
                                     start: low, end: high, chunkEnd: chunkEnd))
        }
        return tokens
    }

    /// Exact source text covered by tokens (including trailing punctuation of the last token).
    static func text(of tokens: [HindiToken], in source: String) -> String {
        guard let first = tokens.first, let last = tokens.last else { return "" }
        return String(source[first.start..<last.chunkEnd])
    }

    /// Splits a sentence into clauses before "ab" (now) when a clause precedes it, because
    /// transcripts often drop the punctuation between "यह final है" and "अब vendor ...".
    static func clauses(of tokens: [HindiToken]) -> [[HindiToken]] {
        var result: [[HindiToken]] = []
        var current: [HindiToken] = []
        for token in tokens {
            if token.key == "ab", current.count >= 2 {
                result.append(current)
                current = []
            }
            current.append(token)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Stable key used to recognize a sentence regardless of end punctuation.
    static func claimKey(_ sentence: String) -> String {
        let trimmed = sentence.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ".!?,;:\u{0964}\"\u{201C}\u{201D}")))
        return trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    static func lowercaseFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        let rest = text.dropFirst()
        // Keep acronyms and names such as "SEO" or "iPhone" intact.
        if let second = rest.first, second.isUppercase { return text }
        return first.lowercased() + rest
    }

    // MARK: - Refusal and acceptance cues (Devanagari only)

    static func isRefusal(_ sentence: String) -> Bool {
        guard containsDevanagari(sentence) else { return false }
        let keys = tokenize(sentence).map { $0.key }
        guard keys.contains("nahi") else { return false }
        let cues: [String] = ["paunga", "paungi", "payega", "payegi", "paoge", "sakta", "sakti", "sakte"]
        for cue in cues where keys.contains(cue) { return true }
        return keys.contains("mujhse")
    }

    static func hasAcceptanceCue(_ sentence: String) -> Bool {
        guard containsDevanagari(sentence) else { return false }
        let keys = tokenize(sentence).map { $0.key }
        if keys.contains("nahi") { return false }
        for cue in ["haan", "zaroor", "bilkul", "ji"] where keys.contains(cue) { return true }
        return keys.contains("thik") && keys.contains("hai")
    }

    // MARK: - Transliteration and name matching

    private static func consonant(_ code: UInt32) -> String? {
        switch code {
        case 0x0915: return "k"
        case 0x0916: return "kh"
        case 0x0917: return "g"
        case 0x0918: return "gh"
        case 0x0919: return "n"
        case 0x091A: return "ch"
        case 0x091B: return "chh"
        case 0x091C: return "j"
        case 0x091D: return "jh"
        case 0x091E: return "n"
        case 0x091F: return "t"
        case 0x0920: return "th"
        case 0x0921: return "d"
        case 0x0922: return "dh"
        case 0x0923: return "n"
        case 0x0924: return "t"
        case 0x0925: return "th"
        case 0x0926: return "d"
        case 0x0927: return "dh"
        case 0x0928: return "n"
        case 0x092A: return "p"
        case 0x092B: return "ph"
        case 0x092C: return "b"
        case 0x092D: return "bh"
        case 0x092E: return "m"
        case 0x092F: return "y"
        case 0x0930: return "r"
        case 0x0932: return "l"
        case 0x0933: return "l"
        case 0x0935: return "v"
        case 0x0936: return "sh"
        case 0x0937: return "sh"
        case 0x0938: return "s"
        case 0x0939: return "h"
        default: return nil
        }
    }

    private static func vowelSign(_ code: UInt32) -> String? {
        switch code {
        case 0x093E: return "a"
        case 0x093F: return "i"
        case 0x0940: return "ee"
        case 0x0941: return "u"
        case 0x0942: return "oo"
        case 0x0943: return "ri"
        case 0x0945: return "e"
        case 0x0947: return "e"
        case 0x0948: return "ai"
        case 0x0949: return "o"
        case 0x094B: return "o"
        case 0x094C: return "au"
        default: return nil
        }
    }

    private static func independentVowel(_ code: UInt32) -> String? {
        switch code {
        case 0x0905: return "a"
        case 0x0906: return "a"
        case 0x0907: return "i"
        case 0x0908: return "ee"
        case 0x0909: return "u"
        case 0x090A: return "oo"
        case 0x090B: return "ri"
        case 0x090F: return "e"
        case 0x0910: return "ai"
        case 0x0911: return "o"
        case 0x0913: return "o"
        case 0x0914: return "au"
        default: return nil
        }
    }

    /// Rough Devanagari to Latin transliteration with final schwa deletion ("पवन" -> "Pawan").
    static func transliterate(_ word: String) -> String {
        let scalars = Array(normalized(word).unicodeScalars)
        var output = ""
        var index = 0
        var afterInherent = false
        while index < scalars.count {
            let code = scalars[index].value
            let next: UInt32 = index + 1 < scalars.count ? scalars[index + 1].value : 0
            if let letters = consonant(code) {
                var piece = letters
                if code == 0x0935, afterInherent, next != 0x094D, vowelSign(next) == nil { piece = "w" }
                output += piece
                if next == 0x094D {
                    afterInherent = false
                    index += 2
                } else if let sign = vowelSign(next) {
                    output += sign
                    afterInherent = false
                    index += 2
                } else {
                    output += "a"
                    afterInherent = true
                    index += 1
                }
                continue
            }
            if let vowel = independentVowel(code) {
                output += vowel
                afterInherent = false
                index += 1
                continue
            }
            if code == 0x0902 { output += "n"; afterInherent = false; index += 1; continue }
            if code == 0x0903 { output += "h"; afterInherent = false; index += 1; continue }
            output.unicodeScalars.append(scalars[index])
            afterInherent = false
            index += 1
        }
        if afterInherent, output.hasSuffix("a") { output.removeLast() }
        return capitalizeFirst(output)
    }

    /// Consonant skeleton used to compare names across scripts and spellings.
    static func skeleton(_ text: String) -> String {
        let latin = containsDevanagari(text) ? transliterate(text) : text
        var letters: [Character] = []
        for character in latin.lowercased() where character >= "a" && character <= "z" { letters.append(character) }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        var result = ""
        for (position, letter) in letters.enumerated() {
            var mapped: String? = nil
            if vowels.contains(letter) {
                if position == 0 { mapped = "a" }
            } else if letter == "h" {
                if position == 0 || vowels.contains(letters[position - 1]) { mapped = "h" }
            } else if letter == "w" {
                mapped = "v"
            } else if letter == "z" {
                mapped = "j"
            } else if letter == "q" || letter == "c" {
                mapped = "k"
            } else if letter == "f" {
                mapped = "p"
            } else if letter == "x" {
                mapped = "ks"
            } else {
                mapped = String(letter)
            }
            guard let value = mapped else { continue }
            if let last = result.last, String(last) == value { continue }
            result += value
        }
        return result
    }

    private static func editDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        var previous: [Int] = Array(0...rhs.count)
        for (i, left) in lhs.enumerated() {
            var current: [Int] = [i + 1]
            for (j, right) in rhs.enumerated() {
                let cost = left == right ? 0 : 1
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + cost))
            }
            previous = current
        }
        return previous[rhs.count]
    }

    static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = skeleton(lhs)
        let right = skeleton(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }
        if left.count >= 4, right.count >= 4 {
            return editDistance(Array(left), Array(right)) <= 1
        }
        return false
    }

    /// The attendee a spoken name refers to, matching across scripts ("पवन" -> "Pawan").
    static func matchParticipant(_ spoken: String, participants: [String]) -> String? {
        var matches: [String] = []
        for person in participants {
            let words = person.split(separator: " ").map(String.init)
            var hit = namesMatch(spoken, person)
            if !hit, let first = words.first { hit = namesMatch(spoken, first) }
            if hit { matches.append(person) }
        }
        return matches.first
    }

    /// Display name for a spoken name that is not a known attendee.
    static func displayName(_ spoken: String) -> String {
        containsDevanagari(spoken) ? transliterate(spoken) : spoken
    }
}
