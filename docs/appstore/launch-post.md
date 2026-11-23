# Launch posts

Fill the `<...>` fields. Read each subreddit's self-promotion rules first (r/iOSapps usually asks for a "Developer" flair and an App Store link; r/productivity restricts promotion, so post there only if the rules allow it or ask the moderators). Reply to every comment honestly, including "it does not do X".

## Reddit (r/iOSapps, adapt for r/productivity)

**Title:** I built an iPhone meeting recorder that writes minutes fully on-device (no account, Hindi and English)

**Body:**

I got tired of meeting recorders that upload my audio to a server and want an account. So I built Manent. I am the developer.

What it does:

- Records a meeting with live captions.
- Afterwards it writes minutes: summary, decisions, open issues, action items with owners and deadlines.
- Separates speakers, and you can name a voice once so it is recognised later.
- Works with Hindi, English and mixed Hinglish.
- Vidur, a small assistant, answers questions about your own meetings and points to the source.
- Exports a PDF, and can send action items to Reminders.

How it stays private: speech recognition (Whisper), speaker separation and the language model (Qwen3 1.7B) all run on your iPhone. There is no account, no analytics and no ads. Recordings, transcripts and minutes stay on the phone. The only network use is downloading the open models once from Hugging Face.

Honest limits:

- The models are big: roughly 0.5 to 1.3 GB per download, so do it on Wi-Fi.
- A 1.7B model on a phone makes mistakes with names, numbers and dates. Treat the minutes as a draft and review them. There is a review step before you share.
- Analysis of a long meeting takes a few minutes and uses battery. Older iPhones are slower.
- Hindi quality is decent for clear speech and weaker with heavy background noise or fast code-switching.
- It is a v1. I would like to hear what breaks.

It is free. <App Store link>. Open-source licences are in Settings, About and Licences. Feedback and bug reports: <support email or issue link>.

## X / LinkedIn (short)

> I just released Manent, an iPhone meeting recorder that writes the minutes on the phone itself. No account, no cloud, no ads. Hindi, English and Hinglish. Recordings and minutes never leave your device. Free. <App Store link>
>
> It uses open models (Whisper, Qwen3) and the minutes are drafts you review. Feedback welcome.

LinkedIn addition (one line): "Built because I did not want client meeting audio on someone else's server."

## Do not claim

- "100% accurate", "replaces note takers", or any accuracy figure you have not measured (see `docs/EVALUATION.md` before quoting numbers).
- "Works with no internet" without mentioning the first model download.
- "Zero data collection" in a way that suggests Apple collects nothing (App Store and TestFlight data belong to Apple).
