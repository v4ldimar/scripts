import subprocess
import sys

if len(sys.argv) != 2:
    print("Usage: python get_test_commits.py <azure_devops_repo_url>")
    sys.exit(1)

AZURE_DEVOPS_REPO_URL = sys.argv[1].rstrip('/')

# Run git log and capture commits with 'test' in the message
git_log_cmd = ['git', 'log', '--grep=test', '--pretty=format:%H %s', '--first-parent', 'HEAD']
log_output = subprocess.check_output(git_log_cmd, encoding="utf-8")

# Format each matching commit into markdown
md_list = []
for line in log_output.strip().split('\n'):
    if not line.strip():
        continue
    commit_hash, *message = line.split()
    message_text = ' '.join(message)
    commit_url = f"{AZURE_DEVOPS_REPO_URL}/commit/{commit_hash}"
    md_list.append(f"- [{message_text}]({commit_url})")

# Output the markdown list
print("\n".join(md_list))

