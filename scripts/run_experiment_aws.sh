#!/usr/bin/env bash
# =============================================================================
# run_experiment_aws.sh - Run the full benchmark experiment on AWS
# =============================================================================
# Deploys infrastructure via Terraform, runs JMeter on a cloud EC2 instance,
# pulls results back locally, tears down, repeats for each architecture,
# then generates charts locally.
#
# Prerequisites:
#   - terraform, ssh, scp on your machine
#   - terraform.tfvars in terraform/monolith/ and terraform/microservices/
#   - SSH key pair matching the key_name in your tfvars
#   - AWS credentials configured (aws configure / env vars)
#   - Run ./scripts/setup.sh first (for Python .venv)
#
# Usage:
#   SSH_KEY=~/.ssh/my-key.pem ./scripts/run_experiment_aws.sh
#
# Options (env vars):
#   SSH_KEY=...        Path to SSH private key (REQUIRED)
#   THREADS=50         Concurrent threads (default: 50)
#   DURATION=600       Test duration in seconds (default: 600)
#   WARMUP=120         Warmup duration in seconds (default: 120)
#   RAMP_UP=30         Ramp-up time in seconds (default: 30)
#   SKIP_DESTROY=false Keep infra alive after each test (default: false)
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SSH_KEY="${SSH_KEY:-}"
THREADS="${THREADS:-50}"
DURATION="${DURATION:-600}"
WARMUP="${WARMUP:-120}"
RAMP_UP="${RAMP_UP:-30}"
SKIP_DESTROY="${SKIP_DESTROY:-false}"

# Create timestamped run directory
RUN_DIR="$RESULTS_DIR/$TIMESTAMP"
mkdir -p "$RUN_DIR"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
SSH_USER="ec2-user"

# ---------------------------------------------------------------------------
# Safety-net: destroy any deployed infrastructure on unexpected exit
# ---------------------------------------------------------------------------
MONO_DEPLOYED=false
MICRO_DEPLOYED=false

cleanup_on_exit() {
  local exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    return 0
  fi
  warn "Script exited with code $exit_code — running safety-net cleanup..."

  if [[ "$SKIP_DESTROY" == "true" ]]; then
    warn "SKIP_DESTROY=true — skipping automatic cleanup. Remember to destroy manually!"
    return 0
  fi

  if [[ "$MONO_DEPLOYED" == "true" ]]; then
    warn "Destroying leftover monolith infrastructure..."
    terraform -chdir="$PROJECT_DIR/terraform/monolith" destroy -auto-approve -input=false || true
  fi

  if [[ "$MICRO_DEPLOYED" == "true" ]]; then
    warn "Destroying leftover microservices infrastructure..."
    terraform -chdir="$PROJECT_DIR/terraform/microservices" destroy -auto-approve -input=false || true
  fi
}
trap cleanup_on_exit EXIT

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
MISSING=()
[[ -z "$SSH_KEY" ]] && {
  error "SSH_KEY is required. Usage: SSH_KEY=~/.ssh/my-key.pem $0"
  exit 1
}
[[ ! -f "$SSH_KEY" ]] && {
  error "SSH key not found: $SSH_KEY"
  exit 1
}
command -v terraform &>/dev/null || MISSING+=("terraform")
command -v ssh &>/dev/null || MISSING+=("ssh")
command -v scp &>/dev/null || MISSING+=("scp")

if ! detect_python; then
  MISSING+=("python3")
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
  error "Missing required tools: ${MISSING[*]}"
  exit 1
fi

# Detect local JMeter for HTML report generation (optional)
detect_jmeter && LOCAL_JMETER="$JMETER" || LOCAL_JMETER=""

echo ""
echo "============================================"
echo "  Monolith vs Microservices (AWS)"
echo "============================================"
echo "  Threads:    $THREADS"
echo "  Duration:   ${DURATION}s"
echo "  Warmup:     ${WARMUP}s"
echo "  Ramp-up:    ${RAMP_UP}s"
echo "  Run ID:     $TIMESTAMP"
echo "  Output:     $RUN_DIR"
echo "  SSH key:    $SSH_KEY"
echo "  Python:     $PYTHON"
echo "============================================"
echo ""

# ---------------------------------------------------------------------------
# Helper: run SSH command on a remote host
# ---------------------------------------------------------------------------
remote_exec() {
  local host="$1"
  shift
  ssh $SSH_OPTS -i "$SSH_KEY" "$SSH_USER@$host" "$@"
}

# ---------------------------------------------------------------------------
# Helper: wait for SSH to become available
# ---------------------------------------------------------------------------
wait_for_ssh() {
  local name="$1"
  local host="$2"
  local max_retries=60
  local retries=0

  info "Waiting for SSH on $name ($host)..."

  while [[ $retries -lt $max_retries ]]; do
    if ssh $SSH_OPTS -i "$SSH_KEY" -o ConnectTimeout=5 "$SSH_USER@$host" "echo ok" &>/dev/null; then
      info "$name SSH is ready"
      return 0
    fi
    retries=$((retries + 1))
    sleep 5
  done

  error "$name SSH not available after $max_retries attempts"
  return 1
}

# ---------------------------------------------------------------------------
# Helper: wait for app health via JMeter EC2 (curl from inside the VPC)
# ---------------------------------------------------------------------------
wait_for_health() {
  local jmeter_host="$1"
  local target_ip="$2"
  local name="$3"
  local max_retries=60
  local retries=0

  info "Waiting for $name health at $target_ip:8080 (via JMeter EC2)..."

  while [[ $retries -lt $max_retries ]]; do
    if remote_exec "$jmeter_host" "curl -sf http://$target_ip:8080/actuator/health" &>/dev/null; then
      info "$name is healthy"
      return 0
    fi
    retries=$((retries + 1))
    warn "$name not ready (attempt $retries/$max_retries)"
    sleep 10
  done

  error "$name failed health check after $max_retries attempts"
  return 1
}

# ---------------------------------------------------------------------------
# Helper: run JMeter on remote EC2
# ---------------------------------------------------------------------------
run_jmeter_remote() {
  local arch="$1"
  local jmeter_host="$2"
  local target_ip="$3"
  local local_output="$RUN_DIR/${arch}.jtl"
  local local_log="$RUN_DIR/${arch}.log"

  info "Uploading benchmark.jmx to JMeter EC2..."
  scp $SSH_OPTS -i "$SSH_KEY" \
    "$PROJECT_DIR/jmeter/benchmark.jmx" \
    "$SSH_USER@$jmeter_host:/tmp/benchmark.jmx"

  info "Running JMeter for $arch on $jmeter_host -> $target_ip:8080"
  info "  Threads=$THREADS, Duration=${DURATION}s, Warmup=${WARMUP}s"

  remote_exec "$jmeter_host" bash -c "'
        source /etc/profile.d/jmeter.sh 2>/dev/null || true
        /opt/jmeter/bin/jmeter -n \
            -t /tmp/benchmark.jmx \
            -l /tmp/results.jtl \
            -j /tmp/jmeter.log \
            -Jhost=$target_ip \
            -Jport=8080 \
            -Jusers_port=8080 \
            -Jproducts_port=8080 \
            -Jorders_port=8080 \
            -Jthreads=$THREADS \
            -Jduration=$DURATION \
            -Jwarmup=$WARMUP \
            -Jrampup=$RAMP_UP
    '"

  info "Downloading results from JMeter EC2..."
  scp $SSH_OPTS -i "$SSH_KEY" \
    "$SSH_USER@$jmeter_host:/tmp/results.jtl" \
    "$local_output"

  scp $SSH_OPTS -i "$SSH_KEY" \
    "$SSH_USER@$jmeter_host:/tmp/jmeter.log" \
    "$local_log" 2>/dev/null || true

  info "Results saved to: $local_output"

  # Quick summary
  if [[ -f "$local_output" ]]; then
    local total_lines
    total_lines=$(wc -l <"$local_output")
    local total_requests=$((total_lines - 1))
    local error_count
    error_count=$(awk -F',' 'NR>1 && $8=="false"{count++} END{print count+0}' "$local_output")
    info "Total requests: $total_requests | Errors: $error_count"
  fi

  # Generate JMeter HTML dashboard locally
  if [[ -n "$LOCAL_JMETER" ]]; then
    local html_report_dir="$RUN_DIR/${arch}_report"
    info "Generating JMeter HTML report -> $html_report_dir"
    "$LOCAL_JMETER" -g "$local_output" -o "$html_report_dir" || warn "HTML report generation failed (non-fatal)"
  else
    warn "Local JMeter not found — skipping HTML report generation"
  fi
}

# ---------------------------------------------------------------------------
# Test monolith on AWS
# ---------------------------------------------------------------------------
test_monolith_aws() {
  local tf_dir="$PROJECT_DIR/terraform/monolith"

  step "===== Testing MONOLITH on AWS ====="

  if [[ ! -f "$tf_dir/terraform.tfvars" ]]; then
    error "Missing $tf_dir/terraform.tfvars — copy from terraform.tfvars.example and fill in your values"
    exit 1
  fi

  # Deploy
  step "1/5 Deploying monolith infrastructure..."
  terraform -chdir="$tf_dir" init -input=false
  terraform -chdir="$tf_dir" apply -auto-approve -input=false
  MONO_DEPLOYED=true

  # Extract outputs
  local jmeter_ip monolith_ip
  jmeter_ip=$(terraform -chdir="$tf_dir" output -raw jmeter_public_ip)
  monolith_ip=$(terraform -chdir="$tf_dir" output -raw monolith_private_ip)

  info "JMeter EC2:     $jmeter_ip"
  info "Monolith (priv): $monolith_ip"

  # Wait for JMeter SSH + JMeter install + app health
  step "2/5 Waiting for instances..."
  wait_for_ssh "JMeter" "$jmeter_ip"

  # Wait for JMeter to finish installing (user_data may still be running)
  info "Waiting for JMeter installation to complete..."
  for i in $(seq 1 30); do
    if remote_exec "$jmeter_ip" "test -f /opt/jmeter/bin/jmeter" &>/dev/null; then
      info "JMeter is installed"
      break
    fi
    [[ $i -eq 30 ]] && {
      error "JMeter installation timed out"
      return 1
    }
    sleep 10
  done

  step "3/5 Waiting for monolith health..."
  wait_for_health "$jmeter_ip" "$monolith_ip" "Monolith"

  # Benchmark
  step "4/5 Running benchmark..."
  run_jmeter_remote "monolith" "$jmeter_ip" "$monolith_ip"

  # Destroy
  if [[ "$SKIP_DESTROY" != "true" ]]; then
    step "5/5 Destroying monolith infrastructure..."
    terraform -chdir="$tf_dir" destroy -auto-approve -input=false
    MONO_DEPLOYED=false
  else
    warn "5/5 Skipping destroy (SKIP_DESTROY=true)"
  fi

  info "Monolith AWS test complete."
}

# ---------------------------------------------------------------------------
# Test microservices on AWS
# ---------------------------------------------------------------------------
test_microservices_aws() {
  local tf_dir="$PROJECT_DIR/terraform/microservices"

  step "===== Testing MICROSERVICES on AWS ====="

  if [[ ! -f "$tf_dir/terraform.tfvars" ]]; then
    error "Missing $tf_dir/terraform.tfvars — copy from terraform.tfvars.example and fill in your values"
    exit 1
  fi

  # Deploy
  step "1/5 Deploying microservices infrastructure..."
  terraform -chdir="$tf_dir" init -input=false
  terraform -chdir="$tf_dir" apply -auto-approve -input=false
  MICRO_DEPLOYED=true

  # Extract outputs
  local jmeter_ip gateway_ip
  jmeter_ip=$(terraform -chdir="$tf_dir" output -raw jmeter_public_ip)
  gateway_ip=$(terraform -chdir="$tf_dir" output -raw gateway_private_ip)

  info "JMeter EC2:      $jmeter_ip"
  info "Gateway (priv):  $gateway_ip"

  # Wait for JMeter SSH + JMeter install + gateway health
  step "2/5 Waiting for instances..."
  wait_for_ssh "JMeter" "$jmeter_ip"

  info "Waiting for JMeter installation to complete..."
  for i in $(seq 1 30); do
    if remote_exec "$jmeter_ip" "test -f /opt/jmeter/bin/jmeter" &>/dev/null; then
      info "JMeter is installed"
      break
    fi
    [[ $i -eq 30 ]] && {
      error "JMeter installation timed out"
      return 1
    }
    sleep 10
  done

  step "3/5 Waiting for gateway health..."
  wait_for_health "$jmeter_ip" "$gateway_ip" "API Gateway"

  # Benchmark (JMeter -> gateway private IP, same as monolith for fair comparison)
  step "4/5 Running benchmark..."
  run_jmeter_remote "microservices" "$jmeter_ip" "$gateway_ip"

  # Destroy
  if [[ "$SKIP_DESTROY" != "true" ]]; then
    step "5/5 Destroying microservices infrastructure..."
    terraform -chdir="$tf_dir" destroy -auto-approve -input=false
    MICRO_DEPLOYED=false
  else
    warn "5/5 Skipping destroy (SKIP_DESTROY=true)"
  fi

  info "Microservices AWS test complete."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
test_monolith_aws

info "Cooling down for 30 seconds between tests..."
sleep 30

test_microservices_aws

analyze_results "$RUN_DIR" "$WARMUP"

echo ""
info "============================================"
info "  AWS Experiment Complete!"
info "============================================"
info "  Run ID:   $TIMESTAMP"
info "  Results:  $RUN_DIR/"
info "  Charts:   $RUN_DIR/charts/"
info "============================================"
