import json

# Define the base explorer URLs for each chain
explorers = {
    "opSepolia": "https://optimism-sepolia.blockscout.com/address/",
    "arbSepolia": "https://sepolia.arbiscan.io/address/",
    "baseSepolia": "https://sepolia.basescan.org/address/",
    "uniSepolia": "https://unichain-sepolia.blockscout.com/address/"
}

# Load the deployment.json file
with open("deployment.json", "r") as f:
    deployment = json.load(f)

# Create Markdown table header
header = "| Contract Name | Address | opSepolia | arbSepolia | baseSepolia | uniSepolia |\n"
separator = "| --- | --- | --- | --- | --- | --- |\n"

table = header + separator

# Construct a table row for each contract
for contract_name, address in deployment.items():
    row = f"| {contract_name} | {address} | "
    links = []
    for chain, base_url in explorers.items():
        link = f"[Link]({base_url}{address})"
        links.append(link)
    row += " | ".join(links) + " |\n"
    table += row

# Save the Markdown table to deployment_links.md
with open("deployment_links.md", "w") as md_file:
    md_file.write(table)

print("Markdown table saved to deployment_links.md")
