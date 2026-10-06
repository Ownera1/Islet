#!/bin/sh
# Step-0 probe for Claude Desktop support (docs/claude-desktop-support.md).
#
# Read-only. Prints counts, file/field names and value *shapes* only: no
# token, prompt, title, reply or other conversation content leaves this
# script. String values are shown only when they look like an enum
# (`five_hour`, `allowed`); numbers are reduced to their range class.
#
#   ./scripts/probe-claude-desktop.sh            # steps 0.3, 0.4, 0.5
#   ./scripts/probe-claude-desktop.sh hook-log   # step 0.1/0.2 probe lines
set -eu

SUPPORT="$HOME/Library/Application Support/Claude"
COWORK="$SUPPORT/local-agent-mode-sessions"
PROJECTS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
BRIDGE_LOG="${BORINGNOTCH_BRIDGE_LOG:-/tmp/notch-agent-bridge.log}"

if [ "${1:-}" = "hook-log" ]; then
  echo "== 0.1 / 0.2: bridge probe lines (BORINGNOTCH_DEBUG=1 only) =="
  if [ -f "$BRIDGE_LOG" ]; then
    # The probe and routing lines carry no payload; still, print only them.
    grep -E '\] (probe |event=)' "$BRIDGE_LOG" | sed -E 's/session=[^ ]+/session=<id>/' | tail -n 60
  else
    echo "no log at $BRIDGE_LOG (is BORINGNOTCH_DEBUG set for the hook process?)"
  fi
  exit 0
fi

echo "== 0.3: Cowork session store =="
if [ -d "$COWORK" ]; then
  meta=$(find "$COWORK" -mindepth 3 -maxdepth 3 -type f -name 'local_*.json' 2>/dev/null | wc -l | tr -d ' ')
  audit=$(find "$COWORK" -mindepth 4 -maxdepth 4 -type f -path '*/local_*/audit.jsonl' 2>/dev/null | wc -l | tr -d ' ')
  echo "local_<id>.json files:        $meta"
  echo "local_<id>/audit.jsonl files: $audit"
  newest=$(find "$COWORK" -mindepth 3 -maxdepth 3 -type f -name 'local_*.json' -exec stat -f '%m %N' {} + 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-)
  if [ -n "$newest" ]; then
    echo "keys of the newest metadata file:"
    /usr/bin/perl -MJSON::PP -0777 -ne '
      my $j = eval { JSON::PP->new->decode($_) } or exit;
      print "  ", join(", ", sort keys %$j), "\n";' "$newest"
    echo "audit record types of that session (count, type/subtype):"
    dir="${newest%.json}"
    [ -f "$dir/audit.jsonl" ] && /usr/bin/perl -MJSON::PP -ne '
      my $j = eval { JSON::PP->new->decode($_) } or next;
      my $t = $j->{type} // "?"; $t .= "/" . $j->{subtype} if defined $j->{subtype} && !ref $j->{subtype};
      $c{$t}++; END { printf "  %6d %s\n", $c{$_}, $_ for sort keys %c }' "$dir/audit.jsonl"
  fi
else
  echo "not found: $COWORK"
fi

echo
echo "== 0.4: rate-limit records on disk =="
# Shape of every matching record, values reduced to type / range class.
shape() {
  /usr/bin/perl -MJSON::PP -ne '
    next unless /"type":"rate_limit_event"|"rate_limit_info"/;
    my $j = eval { JSON::PP->new->decode($_) } or next;
    sub cls {
      my $v = shift;
      if (ref $v eq "HASH") { return "{" . join(",", map { "\"$_\":" . cls($v->{$_}) } sort keys %$v) . "}" }
      if (ref $v eq "ARRAY") { return "[" . (@$v ? cls($v->[0]) : "") . "]" }
      if (JSON::PP::is_bool($v)) { return "<bool>" }
      return "null" unless defined $v;
      if ($v =~ /^-?\d+(\.\d+)?([eE][-+]?\d+)?$/ && !($v =~ /^0\d/)) {
        return "<epoch_ms>" if $v =~ /^\d{13}$/;
        return "<epoch_s>" if $v =~ /^\d{10}(\.\d+)?$/;
        return "<0..1>" if $v >= 0 && $v <= 1;
        return "<0..100>" if $v >= 0 && $v <= 100;
        return "<num>";
      }
      return "\"<iso8601>\"" if $v =~ /^\d{4}-\d\d-\d\dT/;
      return "\"$v\"" if $v =~ /^[a-z_]{1,32}$/;
      return "\"<str>\"";
    }
    my %top = map { $_ => 1 } keys %$j;
    my $info = exists $j->{rate_limit_info} ? cls($j->{rate_limit_info}) : "-";
    print "type=", ($j->{type} // "?"), " keys=[", join(",", sort keys %top), "] rate_limit_info=", $info, "\n";' "$@"
}
for label in "Cowork audit.jsonl:$COWORK" "Claude Code projects:$PROJECTS"; do
  name=${label%%:*}; root=${label#*:}
  echo "-- $name"
  if [ ! -d "$root" ]; then echo "   not found"; continue; fi
  files=$(grep -rlE --include='*.jsonl' '"type":"rate_limit_event"|"rate_limit_info"' "$root" 2>/dev/null || true)
  if [ -z "$files" ]; then echo "   no rate_limit_event / rate_limit_info records"; continue; fi
  echo "   files with records: $(printf '%s\n' "$files" | wc -l | tr -d ' ')"
  printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 cat | shape | sort | uniq -c | sort -rn | head -n 15 | sed 's/^/   /'
  latest=$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 stat -f '%m' | sort -rn | head -n 1)
  echo "   newest such file modified: $(date -r "$latest" '+%Y-%m-%d %H:%M')"
done

echo
echo "== 0.5: Claude keychain items (service names only) =="
# dump-keychain without -d prints attributes, never secret data.
security dump-keychain 2>/dev/null | grep -i '"svce".*claude' | sed -E 's/.*="?([^"]*)"?$/  \1/' | sort -u || true
