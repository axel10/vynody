import os
import re
import sys
import json
import urllib.request

def extract_changelog(version):
    changelog_path = 'changelog.md'
    if not os.path.exists(changelog_path):
        print(f"Error: {changelog_path} not found.")
        return ""
        
    with open(changelog_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    # Match "### <version>" and capture content until the next "###" or EOF
    escaped_version = re.escape(version)
    pattern = rf"###\s+{escaped_version}\s*\n([\s\S]*?)(?=\n###|$)"
    match = re.search(pattern, content)
    
    if not match:
        print(f"Warning: No changelog entry found for version {version}")
        return ""
        
    return match.group(1).strip()

def translate_text(text, api_key, model="google/gemini-3.1-flash-lite"):
    if not text:
        return ""
        
    prompt = (
        "You are a professional software release translator. Translate the following Chinese changelog list "
        "into clear, natural, and professional English release notes. Keep the list format (using bullet points). "
        "Only return the final English translation, without any introduction, greetings, explanations, markdown code blocks, or other text.\n\n"
        f"Changelog:\n{text}"
    )
    
    url = "https://openrouter.ai/api/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/axel10/vibe_flow",
        "X-Title": "Vynody Release Bot"
    }
    
    data = {
        "model": model,
        "messages": [
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.2
    }
    
    req = urllib.request.Request(
        url, 
        data=json.dumps(data).encode('utf-8'), 
        headers=headers,
        method='POST'
    )
    
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            res_data = json.loads(response.read().decode('utf-8'))
            translation = res_data['choices'][0]['message']['content'].strip()
            return translation
    except Exception as e:
        print(f"Error calling OpenRouter API: {e}")
        return ""

def main():
    if len(sys.argv) < 2:
        print("Usage: python translate_release_notes.py <tag_name>")
        sys.exit(1)
        
    tag_name = sys.argv[1]
    # Strip leading 'v'
    version = tag_name[1:] if tag_name.startswith('v') else tag_name
    
    api_key = os.environ.get("OPENROUTER_API_KEY")
    model = os.environ.get("OPENROUTER_MODEL", "google/gemini-3.1-flash-lite")
    
    chinese_changelog = extract_changelog(version)
    
    if not chinese_changelog:
        with open("release_notes.md", "w", encoding="utf-8") as f:
            f.write("# Release Notes\n\n")
        return
        
    english_changelog = ""
    if api_key:
        print(f"Translating changelog for version {version} using OpenRouter ({model})...")
        english_changelog = translate_text(chinese_changelog, api_key, model)
    else:
        print("Warning: OPENROUTER_API_KEY is not set. Skipping AI translation.")
        
    with open("release_notes.md", "w", encoding="utf-8") as f:
        f.write("## What's New / 更新日志\n\n")
        
        if english_changelog:
            f.write("### 🇬🇧 English\n")
            f.write(english_changelog + "\n\n")
            
        f.write("### 🇨🇳 中文\n")
        f.write(chinese_changelog + "\n\n")
        f.write("---\n")

if __name__ == "__main__":
    main()
