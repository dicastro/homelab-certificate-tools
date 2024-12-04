#!/bin/bash

# Default duration
DEFAULT_DURATION=$((100 * 365))

# Accepted SAN types
VALID_SAN_TYPES=("IP" "DNS")

# Function to display help message
show_help() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  --cn <CN>           Common Name for the certificate (required)"
  echo "  --duration <days>    Duration for the certificate (default: 36500 days)"
  echo "  --san <type>:<value> Subject Alternative Name (SAN), can be repeated for multiple SANs"
  echo "                        Accepted types: IP, DNS"
  echo "  --ca-cert <file>     Path to the CA certificate (required)"
  echo "  --ca-key <file>      Path to the CA private key (required)"
  echo "  --ca-serial <file>   Path to the CA serial file (required)"
  echo "  --output-dir <dir>   Directory to save the generated files (default: current directory)"
  echo "  --help               Display this help message"
}

# Function to validate Common Name (CN)
validate_cn() {
  local cn="$1"
  [[ -n "$cn" ]] && return 0 || return 1
}

# Function to validate SAN type (IP or DNS)
validate_san_type() {
  local type="$1"
  if [[ " ${VALID_SAN_TYPES[@]} " =~ " ${type^^} " ]]; then
    return 0
  else
    return 1
  fi
}

# Function to validate SAN (IP or DNS)
validate_san_value() {
  local type="$1"
  local value="$2"

  if [[ "$type" == "IP" ]]; then
    if [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      return 0
    else
      return 1
    fi
  elif [[ "$type" == "DNS" ]]; then
    if [[ "$value" =~ ^[a-zA-Z0-9.-]+$ ]]; then
      return 0
    else
      return 1
    fi
  fi

  return 1
}

# Function to validate duration
validate_duration() {
  local duration="$1"
  [[ "$duration" =~ ^[0-9]+$ ]] && [[ "$duration" -gt 0 ]] && return 0 || return 1
}

# Function to validate Y/N input
validate_yn() {
  local input="$1"
  [[ "$input" =~ ^(y|n|Y|N)$ ]] && return 0 || return 1
}

# Function to prompt for input with validation, showing default value if provided
prompt_input() {
  local prompt="$1"
  local validate_func="$2"
  shift 2
  local default_value="$1"
  shift 1
  local input

  while true; do
    if [[ -n "$default_value" ]]; then
      read -p "$prompt [default: $default_value]: " input
      input="${input:-$default_value}"
    else
      read -p "$prompt: " input
    fi

    if [[ -n "${validate_func}" ]]; then
      if "${validate_func}" "$@" "${input}"; then
        echo "${input}"
        return 0
      else
        echo "Invalid input. Please try again." >&2
      fi
    else
      echo "${input}"
      return 0
    fi
  done
}

# Parse named arguments
CN=""
DURATION="$DEFAULT_DURATION"
SAN_LIST=()
CA_CERT=""
CA_KEY=""
CA_SERIAL=""
OUTPUT_DIR="."

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --cn) CN="$2"; shift ;;
    --duration) DURATION="$2"; shift ;;
    --san) SAN_LIST+=("$2"); shift ;;
    --ca-cert) CA_CERT="$2"; shift ;;
    --ca-key) CA_KEY="$2"; shift ;;
    --ca-serial) CA_SERIAL="$2"; shift ;;
    --output-dir) OUTPUT_DIR="$2"; shift ;;
    --help) show_help; exit 0 ;;
    *) echo "Unknown parameter: $1"; show_help; exit 1 ;;
  esac
  shift
done

# Validate or prompt for CN
if ! validate_cn "$CN"; then
  CN=$(prompt_input "Enter Common Name (CN)" validate_cn "")
fi

# Validate or prompt for duration
if ! validate_duration "$DURATION"; then
  DURATION=$(prompt_input "Enter certificate duration (days)" validate_duration "$DEFAULT_DURATION")
fi

# Validate or prompt for CA certificate, key, and serial file
if [[ -z "$CA_CERT" ]]; then
  CA_CERT=$(prompt_input "Enter path to CA certificate" validate_cn "")
fi
if [[ -z "$CA_KEY" ]]; then
  CA_KEY=$(prompt_input "Enter path to CA private key" validate_cn "")
fi
if [[ -z "$CA_SERIAL" ]]; then
  CA_SERIAL=$(prompt_input "Enter path to CA serial file" validate_cn "")
fi

# Validate or prompt for destination directory
if [[ ! -d "$OUTPUT_DIR" ]]; then
  echo "Directory $OUTPUT_DIR does not exist. Creating it..."
  mkdir -p "$OUTPUT_DIR"
fi

# Handle SAN entries
if [[ "${#SAN_LIST[@]}" -eq 0 ]]; then
  while true; do
    add_san=$(prompt_input "Do you want to add a Subject Alternative Name (SAN)? (y/n)" validate_yn "")
    if [[ "$add_san" =~ ^(n|N)$ ]]; then
      break
    fi
    san_type=$(prompt_input "Enter SAN type (IP/DNS)" validate_san_type "")
    san_type="${san_type^^}"
    san_value_prompt_message="Enter ${san_type} value"
    san_value=$(prompt_input "Enter ${san_type} value" "validate_san_value" "" "${san_type}")

    SAN_LIST+=("$san_type:$san_value")
  done
fi

# Prepare SAN extension
SAN_EXTENSION=""
for san in "${SAN_LIST[@]}"; do
  SAN_EXTENSION+="${san/,/, }"
done

# Generate private key
PRIVATE_KEY="${OUTPUT_DIR}/${CN}_key.pem"
CSR="${OUTPUT_DIR}/${CN}.csr"
CERT="${OUTPUT_DIR}/${CN}.crt"

echo "Generating private key..."
openssl genrsa -out "$PRIVATE_KEY" 2048

# Generate CSR
echo "Generating CSR..."
openssl req -new -key "$PRIVATE_KEY" -out "$CSR" -subj "/CN=$CN"

# Sign certificate
echo "Signing certificate..."
openssl x509 -req -in "$CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAserial "$CA_SERIAL" \
  -out "$CERT" -days "$DURATION" -sha256 \
  -extfile <(printf "subjectAltName=$SAN_EXTENSION")

# Delete CSR
rm "$CSR"

echo "Certificate signed successfully:"
echo "  Private Key: $PRIVATE_KEY"
echo "  Certificate: $CERT"
