"""Resolve public model metadata into an immutable, checksummed download manifest.
This tool never reads meeting content. Run only when deliberately updating models.
"""
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen


def snapshot(repo, select, prefix=""):
    with urlopen(f"https://huggingface.co/api/models/{repo}?blobs=true") as response:
        model = json.load(response)
    files = []
    for sibling in model["siblings"]:
        path = sibling["rfilename"]
        if not select(path):
            continue
        url = f"https://huggingface.co/{repo}/resolve/{model['sha']}/{path}"
        digest = sibling.get("lfs", {}).get("sha256")
        size = sibling.get("size")
        if not digest:
            with urlopen(url) as response:
                content = response.read()
            digest, size = hashlib.sha256(content).hexdigest(), len(content)
        files.append(dict(path=prefix + path, url=url, sha256=digest, bytes=size))
    if not files:
        raise RuntimeError(f"No assets found for {repo}")
    return model["sha"], files


def main():
    entries = []
    for identifier, folder, tokenizer in [
        ("whisper-small", "openai_whisper-small", "openai/whisper-small"),
        ("whisper-large", "openai_whisper-large-v3-v20240930_626MB", "openai/whisper-large-v3"),
    ]:
        revision, files = snapshot("argmaxinc/whisperkit-coreml", lambda p: p.startswith(folder + "/"))
        for f in files:
            f["path"] = f["path"][len(folder) + 1:]
        tok_rev, tok_files = snapshot(tokenizer, lambda p: p in ("tokenizer.json", "tokenizer_config.json", "config.json"))
        # The model export may also contain config.json. Tokenizer configuration
        # owns these root paths; never download two different files to one path.
        tokenizer_paths = {f["path"] for f in tok_files}
        files = [f for f in files if f["path"] not in tokenizer_paths]
        entries.append(dict(id=identifier, name=folder, revision=revision + ":" + tok_rev, files=files + tok_files))
    revision, files = snapshot("FluidInference/speaker-diarization-coreml", lambda p: p.startswith(tuple(n + ".mlmodelc/" for n in ("Segmentation", "Embedding", "FBank", "PldaRho"))) or p == "plda-parameters.json")
    entries.append(dict(id="diarization", name="FluidAudio offline VBx", revision=revision, files=files))
    for identifier, repo, filename in [
        ("qwen-3.5-2b", "unsloth/Qwen3.5-2B-GGUF", "Qwen3.5-2B-Q4_K_M.gguf"),
    ]:
        revision, files = snapshot(repo, lambda p: p == filename)
        files[0]["path"] = "model.gguf"
        entries.append(dict(id=identifier, name=filename, revision=revision, files=files))
    output = Path("OfflineEngineKit/Sources/OfflineEngineKit/Resources/models.json")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(entries, indent=2) + "\n", encoding="utf-8")
    for entry in entries:
        print(entry["id"], len(entry["files"]), sum(f["bytes"] for f in entry["files"]))


if __name__ == "__main__":
    main()
