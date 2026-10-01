#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JQ_BIN="${JQ_BIN:-$(command -v jq)}"
source "$ROOT_DIR/Resources/metadata_helpers.sh"

fixture=$(<"$ROOT_DIR/tests/phase1_metadata_fixture.json")
te_json_is_valid "$fixture"

video=$(te_first_stream_json "$fixture" "video")
audio=$(te_first_stream_json "$fixture" "audio")

[[ "$(te_json_value "$video" '.codec_tag_string')" == "apch" ]]
[[ "$(te_json_value "$video" '.bit_rate')" == "193000000" ]]
[[ "$(te_json_value "$video" '.width')" == "1920" ]]
[[ "$(te_json_value "$video" '.height')" == "1080" ]]
[[ "$(te_json_value "$video" '.display_aspect_ratio')" == "16:9" ]]
[[ "$(te_rate_to_decimal "$(te_json_value "$video" '.avg_frame_rate // .r_frame_rate')")" == "29.97" ]]
[[ "$(te_json_value "$video" '.field_order')" == "progressive" ]]
[[ "$(te_json_value "$video" '.pix_fmt')" == "yuv422p10le" ]]
[[ "$(te_language_tags "$fixture" "video")" == "stream 0: eng" ]]

[[ "$(te_stream_count "$fixture" "audio")" == "1" ]]
[[ "$(te_json_value "$audio" '.codec_name')" == "pcm_s24le" ]]
[[ "$(te_json_value "$audio" '.channels')" == "2" ]]
[[ "$(te_json_value "$audio" '.sample_rate')" == "48000" ]]
[[ "$(te_json_value "$audio" '.bits_per_raw_sample // .bits_per_sample')" == "24" ]]
[[ "$(te_json_value "$audio" '.bit_rate')" == "2304000" ]]
[[ "$(te_language_tags "$fixture" "audio")" == "stream 1: spa" ]]

echo "metadata helper tests passed"
