import Foundation

/// Small word lists and spelling helpers that tell Hindi apart from English words written
/// in Devanagari. Used only by `LiveCaptionLanguageArbiter`; all functions are pure.
enum LiveCaptionLexicon {

    /// Builds a set from lines of space separated words.
    private static func wordSet(_ lines: [String]) -> Set<String> {
        var result = Set<String>()
        for line in lines {
            for word in line.split(whereSeparator: { $0.isWhitespace }) {
                result.insert(String(word))
            }
        }
        return result
    }

    // MARK: Hindi function words

    /// Very common Hindi grammar words. English words written in Devanagari do not use them,
    /// so a single hit is strong evidence that the speaker is really speaking Hindi.
    static let hindiFunctionWords: Set<String> = wordSet([
        "है हैं हूं हूँ हो था थी थे थीं गया गयी गई गए गये रहा रही रहे रहें",
        "का की के को में से पर ने तक लिए साथ बाद पहले",
        "नहीं ना और तो भी ही क्या कि कौन कब कहाँ कहां कैसे क्यों कितना",
        "हम आप मैं मै तुम ये यह वो वह मेरा मेरी मेरे हमारा हमारी हमारे आपका आपकी आपके उन्हें उसे इसे",
        "कर करना करने करते करता करती करें करो कीजिए जाना जाता जाती जाते जाएगा जाऊंगा",
        "लेकिन अगर जो जब तब कुछ बहुत अभी फिर सब कोई क्योंकि इसलिए",
    ])

    // MARK: English loanwords in Devanagari

    /// Common English words as speakers' Hindi recognizers spell them. When the Hindi
    /// result is made of these, the speaker was really talking English.
    static let englishLoanwords: Set<String> = wordSet([
        "मीटिंग मीटिंग्स प्रोजेक्ट प्रोजेक्ट्स डेडलाइन टीम मैनेजर रिपोर्ट प्रेजेंटेशन क्लाइंट कस्टमर",
        "ईमेल मेल फोन मोबाइल लैपटॉप कंप्यूटर सॉफ्टवेयर हार्डवेयर ऐप एप्लिकेशन वेबसाइट इंटरनेट",
        "ऑनलाइन ऑफलाइन अपडेट स्टेटस रिव्यू फीडबैक प्लान प्लानिंग बजट बिजनेस कंपनी ऑफिस ऑफिशियल",
        "सेल्स मार्केटिंग मार्केट प्रोडक्ट प्रोसेस सिस्टम डेटा डेटाबेस सर्वर क्लाउड सिक्योरिटी",
        "पासवर्ड लॉगिन अकाउंट टार्गेट गोल रिजल्ट टास्क शेड्यूल कैलेंडर रिमाइंडर नोट्स नोट",
        "डॉक्यूमेंट फाइल फोल्डर लिंक शेयर फॉरवर्ड कॉल वीडियो ऑडियो रिकॉर्डिंग रिकॉर्ड",
        "ट्रांसक्रिप्ट समरी एजेंडा पॉइंट इश्यू प्रॉब्लम सॉल्यूशन आइडिया सजेशन डिस्कशन डिस्कस",
        "कंफर्म कन्फर्म कैंसल अप्रूव अप्रूवल अपॉइंटमेंट इंटरव्यू रिज्यूमे सैलरी हॉलिडे वीकेंड",
        "संडे मंडे ट्यूजडे वेडनेसडे थर्सडे फ्राइडे सैटरडे",
        "लीडर लीडरशिप मैसेज चैट ग्रुप टाइम टाइमलाइन प्रायोरिटी रिक्वायरमेंट डिलीवरी डिलीवर",
        "रिलीज लॉन्च डिजाइन डेवलपर डेवलपमेंट टेस्टिंग टेस्ट बग फिक्स फीचर वर्जन अपग्रेड",
        "इन्वॉइस पेमेंट बैंक लोन इन्वेस्टमेंट इन्वेस्टर स्टार्टअप फंडिंग रेवेन्यू प्रॉफिट",
        "कॉन्ट्रैक्ट एग्रीमेंट पार्टनर पार्टनरशिप कॉन्फ्रेंस ज़ूम जूम स्लाइड स्क्रीन",
        "एंड द टू ऑफ इज दिस दैट विथ फॉर ऑन यू विल कैन वुड शुड कुड नॉट ओके यस प्लीज सॉरी थैंक्स",
        "थैंक हेलो हैलो हाय गुड मॉर्निंग नाइस राइट लेट्स लेट बट इफ व्हाट वेल अबाउट",
    ])

    // MARK: Script helpers

    static func isDevanagari(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x0900 && scalar.value <= 0x097F
    }

    static func containsDevanagari(_ token: String) -> Bool {
        token.unicodeScalars.contains(where: isDevanagari)
    }

    static func containsLatinLetter(_ token: String) -> Bool {
        token.unicodeScalars.contains { scalar in
            (scalar.value >= 0x41 && scalar.value <= 0x5A) || (scalar.value >= 0x61 && scalar.value <= 0x7A)
        }
    }

    /// True when `token` is a Devanagari-spelled English word: listed, listed without a
    /// plural "s" ending, or spelled like one of `englishTokens` (consonant skeleton match).
    static func isTransliteratedEnglish(_ token: String, englishTokens: [String]) -> Bool {
        if englishLoanwords.contains(token) { return true }
        // Plural: "मीटिंग" + "्स".
        let scalars = Array(token.unicodeScalars)
        if scalars.count > 3, scalars[scalars.count - 1].value == 0x0938, scalars[scalars.count - 2].value == 0x094D {
            var stem = String.UnicodeScalarView()
            stem.append(contentsOf: scalars.dropLast(2))
            if englishLoanwords.contains(String(stem)) { return true }
        }
        let spoken = devanagariSkeleton(token)
        guard spoken.count >= 3 else { return false }
        for word in englishTokens where englishSkeleton(word) == spoken {
            return true
        }
        return false
    }

    // MARK: Consonant skeletons

    /// Consonants of an English word folded into the classes Hindi speakers cannot tell apart
    /// when spelling English in Devanagari ("project" and "प्रोजेक्ट" both give "prskt").
    static func englishSkeleton(_ word: String) -> String {
        var text = word.lowercased().filter { $0.isASCII && $0.isLetter }
        for (pattern, replacement) in [("ph", "p"), ("th", "t"), ("ch", "s"), ("sh", "s"), ("ck", "k"),
                                       ("kn", "n"), ("wh", "v"), ("gh", "")] {
            text = text.replacingOccurrences(of: pattern, with: replacement)
        }
        var result = ""
        for character in text {
            let mapped: String
            switch character {
            case "b", "p", "f": mapped = "p"
            case "d", "t": mapped = "t"
            case "g", "k", "c", "q": mapped = "k"
            case "j", "s", "z": mapped = "s"
            case "x": mapped = "ks"
            case "v", "w": mapped = "v"
            case "l": mapped = "l"
            case "m": mapped = "m"
            case "n": mapped = "n"
            case "r": mapped = "r"
            default: mapped = ""
            }
            for piece in mapped where result.last != piece {
                result.append(piece)
            }
        }
        return result
    }

    /// Same classes for a Devanagari word. Vowels, matras, virama and "h" are ignored.
    static func devanagariSkeleton(_ word: String) -> String {
        var result = ""
        for scalar in word.unicodeScalars {
            let mapped: Character?
            switch scalar.value {
            case 0x0915...0x0918, 0x0958...0x095A: mapped = "k"
            case 0x091A...0x091D, 0x0936...0x0938, 0x095B: mapped = "s"
            case 0x091F...0x0922, 0x0924...0x0927: mapped = "t"
            case 0x092A...0x092D, 0x095E: mapped = "p"
            case 0x092E: mapped = "m"
            case 0x0928, 0x0929, 0x0923, 0x0901, 0x0902: mapped = "n"
            case 0x0930, 0x095C, 0x095D: mapped = "r"
            case 0x0932, 0x0933: mapped = "l"
            case 0x0935: mapped = "v"
            default: mapped = nil
            }
            if let mapped, result.last != mapped {
                result.append(mapped)
            }
        }
        return result
    }
}
