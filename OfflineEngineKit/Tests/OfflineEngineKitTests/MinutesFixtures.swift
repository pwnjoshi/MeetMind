import Foundation
@testable import OfflineEngineKit

struct MinutesFixtureLine {
    let speaker: String?
    let text: String
}

/// The scripted Neha/Pawan dialogue in the four transcript shapes the minutes pipeline must handle.
enum MinutesFixtures {
    /// Devanagari with English words in Latin script, fully punctuated.
    static let devanagari: [MinutesFixtureLine] = [
        MinutesFixtureLine(speaker: "S1", text: "हाय पवन, चलो आज की मीटिंग शुरू करते हैं। आज हमें launch और budget पर बात करनी है।"),
        MinutesFixtureLine(speaker: "S2", text: "हाँ नेहा, ठीक है। पहले launch date की बात कर लेते हैं।"),
        MinutesFixtureLine(speaker: "S1", text: "मुझे लगता है हमें 20 November को launch करना चाहिए। तुम्हें क्या लगता है?"),
        MinutesFixtureLine(speaker: "S2", text: "हाँ, 20 November सही रहेगा। चलो, launch 20 November को ही final करते हैं।"),
        MinutesFixtureLine(speaker: "S1", text: "ठीक है, यह final है। अब vendor के बारे में बात करते हैं।"),
        MinutesFixtureLine(speaker: "S2", text: "मेरे हिसाब से Pune वाला vendor अच्छा है, उसका price भी कम है।"),
        MinutesFixtureLine(speaker: "S1", text: "हाँ, let's go with the Pune vendor."),
        MinutesFixtureLine(speaker: "S1", text: "पवन, क्या तुम Friday तक agenda तैयार कर सकते हो?"),
        MinutesFixtureLine(speaker: "S2", text: "हाँ, ज़रूर। मैं Friday तक agenda बना दूँगा।"),
        MinutesFixtureLine(speaker: "S2", text: "और नेहा, तुम कल तक client को presentation भेज दोगी?"),
        MinutesFixtureLine(speaker: "S1", text: "हाँ, मैं कल तक presentation भेज दूँगी।"),
        MinutesFixtureLine(speaker: "S2", text: "Budget का क्या करें? Marketing के लिए कितना रखें?"),
        MinutesFixtureLine(speaker: "S1", text: "Budget अभी decide नहीं हुआ है। उस पर अगली मीटिंग में बात करेंगे।"),
        MinutesFixtureLine(speaker: "S2", text: "ठीक है। Design change करना है या नहीं, वो भी अभी तय नहीं हुआ।"),
        MinutesFixtureLine(speaker: "S1", text: "हाँ, वो भी pending है। ठीक है, आज के लिए इतना ही। Thank you पवन।")
    ]

    /// The same Devanagari turns with all sentence punctuation removed, so sentences run together.
    static var unpunctuated: [MinutesFixtureLine] {
        devanagari.map { line in
            var text = line.text
            for mark in ["\u{0964}", ",", "?", "."] { text = text.replacingOccurrences(of: mark, with: "") }
            return MinutesFixtureLine(speaker: line.speaker, text: text)
        }
    }

    /// Romanized Hinglish, as Whisper writes it when it does not use Devanagari.
    static let romanized: [MinutesFixtureLine] = [
        MinutesFixtureLine(speaker: "S1", text: "Hi Pawan, chalo aaj ki meeting shuru karte hain. Aaj humein launch aur budget par baat karni hai."),
        MinutesFixtureLine(speaker: "S2", text: "Haan Neha, theek hai. Pehle launch date ki baat kar lete hain."),
        MinutesFixtureLine(speaker: "S1", text: "Mujhe lagta hai humein 20 November ko launch karna chahiye. Tumhe kya lagta hai?"),
        MinutesFixtureLine(speaker: "S2", text: "Haan, 20 November sahi rahega. Chalo, launch 20 November ko hi final karte hain."),
        MinutesFixtureLine(speaker: "S1", text: "Theek hai, yeh final hai. Ab vendor ke baare mein baat karte hain."),
        MinutesFixtureLine(speaker: "S2", text: "Mere hisaab se Pune wala vendor accha hai, uska price bhi kam hai."),
        MinutesFixtureLine(speaker: "S1", text: "Haan, let's go with the Pune vendor."),
        MinutesFixtureLine(speaker: "S1", text: "Pawan, kya tum Friday tak agenda taiyaar kar sakte ho?"),
        MinutesFixtureLine(speaker: "S2", text: "Haan zaroor. Main Friday tak agenda bana dunga."),
        MinutesFixtureLine(speaker: "S2", text: "Aur Neha, tum kal tak client ko presentation bhej dogi?"),
        MinutesFixtureLine(speaker: "S1", text: "Haan, main kal tak presentation bhej dungi."),
        MinutesFixtureLine(speaker: "S2", text: "Budget ka kya karein? Marketing ke liye kitna rakhein?"),
        MinutesFixtureLine(speaker: "S1", text: "Budget abhi decide nahi hua hai. Us par agli meeting mein baat karenge."),
        MinutesFixtureLine(speaker: "S2", text: "Theek hai. Design change karna hai ya nahi, wo bhi abhi tay nahi hua."),
        MinutesFixtureLine(speaker: "S1", text: "Haan, wo bhi pending hai. Theek hai, aaj ke liye itna hi. Thank you Pawan.")
    ]

    /// An English rendering of the same meeting.
    static let english: [MinutesFixtureLine] = [
        MinutesFixtureLine(speaker: "S1", text: "Hi Pawan, let's start the meeting. Today we need to discuss the launch date, the vendor and the budget."),
        MinutesFixtureLine(speaker: "S2", text: "Sure Neha. Let's begin with the launch date."),
        MinutesFixtureLine(speaker: "S1", text: "I think we should launch on 20 November. What do you think?"),
        MinutesFixtureLine(speaker: "S2", text: "Yes, 20 November works for me. We agreed to launch on 20 November."),
        MinutesFixtureLine(speaker: "S1", text: "Great. Now let's talk about the vendor."),
        MinutesFixtureLine(speaker: "S2", text: "In my opinion the Pune vendor is better, and their price is also lower."),
        MinutesFixtureLine(speaker: "S1", text: "Yes, let's go with the Pune vendor."),
        MinutesFixtureLine(speaker: "S1", text: "Pawan, can you prepare the agenda by Friday?"),
        MinutesFixtureLine(speaker: "S2", text: "Yes, sure. I'll prepare the agenda by Friday."),
        MinutesFixtureLine(speaker: "S2", text: "And Neha, can you send the presentation to the client by tomorrow?"),
        MinutesFixtureLine(speaker: "S1", text: "Yes, I'll send the presentation by tomorrow."),
        MinutesFixtureLine(speaker: "S2", text: "What about the budget? How much do we keep for marketing?"),
        MinutesFixtureLine(speaker: "S1", text: "The budget is not decided yet. We will discuss it in the next meeting."),
        MinutesFixtureLine(speaker: "S2", text: "Okay. The design change is also not decided yet."),
        MinutesFixtureLine(speaker: "S1", text: "Yes, that's pending too. Okay, that's all for today. Thank you Pawan.")
    ]

    static func turns(_ lines: [MinutesFixtureLine]) -> [AnalysisTurn] {
        var turns: [AnalysisTurn] = []
        for (index, line) in lines.enumerated() {
            turns.append(AnalysisTurn(id: "t\(index + 1)", text: line.text, start: Double(index * 5),
                                      end: Double(index * 5 + 4), speaker: line.speaker))
        }
        return turns
    }
}
