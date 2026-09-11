extends RefCounted

## Compact battle kinds for Custom Battle. Keep 0/1 as Hearthline / Debt Wings
## so existing tests and FFI stay stable. Not an autoload.

const HEARTHLINE := 0
const DEBT_WINGS := 1
const STOVEBREAKERS := 2
const ASH_WARDENS := 3
const WALK_MAPPERS := 4
const LEDGER_PIECES := 5
const ROLLING_HEARTHS := 6
const CEILING_CLERKS := 7
const COUNT := 8

const RANK_SCREEN := 0
const RANK_LINE := 1
const RANK_OVERWATCH := 2
const RANK_BATTERY := 3
const RANK_TRAIN := 4
const RANK_AIR := 5

## Parent classification for formation / placement. Closed. Not a second combat dialect.
const GROUP_INFANTRY_MELEE := 0
const GROUP_INFANTRY_HYBRID := 1
const GROUP_INFANTRY_RANGE := 2
const GROUP_INFANTRY_SKIRMISH := 3
const GROUP_INFANTRY_ENGINEER := 4
const GROUP_ANTI_AIR := 5
const GROUP_ARTILLERY := 6
const GROUP_SUPPORT := 7
const GROUP_AIR := 8

const GROUP_NAMES: PackedStringArray = [
	"infantry_melee",
	"infantry_hybrid",
	"infantry_range",
	"infantry_skirmish",
	"infantry_engineer",
	"anti_air",
	"artillery",
	"support",
	"air",
]

const NAMES: PackedStringArray = [
	"Hearthline",
	"Debt Wings",
	"Stovebreakers",
	"Ash Wardens",
	"Walk-Mappers",
	"Ledger Pieces",
	"Rolling Hearths",
	"Ceiling Clerks",
]

const SHORT: PackedStringArray = [
	"Hearth",
	"Wings",
	"Stove",
	"Ash",
	"Walk",
	"Ledger",
	"Hearths",
	"Clerks",
]


static func clamp_kind(kind: int) -> int:
	return clampi(kind, 0, COUNT - 1)


static func display_name(kind: int) -> String:
	return String(NAMES[clamp_kind(kind)])


static func short_name(kind: int) -> String:
	return String(SHORT[clamp_kind(kind)])


static func is_air(kind: int) -> bool:
	return clamp_kind(kind) == DEBT_WINGS


static func uses_sheet(kind: int) -> bool:
	var k := clamp_kind(kind)
	return k == HEARTHLINE or k == STOVEBREAKERS or k == ASH_WARDENS or k == WALK_MAPPERS or k == CEILING_CLERKS


static func rank(kind: int) -> int:
	match clamp_kind(kind):
		WALK_MAPPERS:
			return RANK_SCREEN
		STOVEBREAKERS, HEARTHLINE:
			return RANK_LINE
		CEILING_CLERKS:
			return RANK_OVERWATCH
		LEDGER_PIECES:
			return RANK_BATTERY
		ASH_WARDENS, ROLLING_HEARTHS:
			return RANK_TRAIN
		DEBT_WINGS:
			return RANK_AIR
		_:
			return RANK_LINE


static func group(kind: int) -> int:
	match clamp_kind(kind):
		STOVEBREAKERS:
			return GROUP_INFANTRY_MELEE
		WALK_MAPPERS:
			return GROUP_INFANTRY_SKIRMISH
		ASH_WARDENS:
			return GROUP_INFANTRY_ENGINEER
		CEILING_CLERKS:
			return GROUP_ANTI_AIR
		LEDGER_PIECES:
			return GROUP_ARTILLERY
		ROLLING_HEARTHS:
			return GROUP_SUPPORT
		DEBT_WINGS:
			return GROUP_AIR
		_:
			return GROUP_INFANTRY_HYBRID


static func group_name(kind: int) -> String:
	return String(GROUP_NAMES[group(kind)])


## Lower = closer to the Attack Column tip / wedge point. Melee, then hybrid, then range.
static func line_priority(kind: int) -> int:
	match group(kind):
		GROUP_INFANTRY_MELEE:
			return 0
		GROUP_INFANTRY_HYBRID:
			return 1
		GROUP_INFANTRY_RANGE:
			return 2
		_:
			return 3


## Presentation tracer cadence only — combat authority is Rust attack_interval.
static func tracer_interval(kind: int) -> float:
	match clamp_kind(kind):
		STOVEBREAKERS:
			return 0.07
		WALK_MAPPERS, CEILING_CLERKS:
			return 0.16
		ASH_WARDENS:
			return 0.22
		LEDGER_PIECES:
			return 0.42
		ROLLING_HEARTHS:
			return 0.55
		DEBT_WINGS:
			return 0.28
		_:
			return 0.11


## How a kind's baked ST_FIRE should look. Presentation only — not a second combat brain.
## Every ranged shot is a gun or ordnance (tracer, slug, shell, bomb). No energy beams.
const SHOT_NONE := 0
const SHOT_RIFLE := 1
const SHOT_HEAT := 2
const SHOT_SATCHEL := 3
const SHOT_SHELL := 4
const SHOT_FLAK := 5
const SHOT_BOMB := 6


static func shot_style(kind: int) -> int:
	match clamp_kind(kind):
		STOVEBREAKERS:
			return SHOT_HEAT
		ASH_WARDENS:
			return SHOT_SATCHEL
		LEDGER_PIECES:
			return SHOT_SHELL
		ROLLING_HEARTHS:
			return SHOT_NONE
		CEILING_CLERKS:
			return SHOT_FLAK
		DEBT_WINGS:
			return SHOT_BOMB
		_:
			return SHOT_RIFLE


const STYLE_HOLD := 0
const STYLE_CHARGE := 1
const STYLE_DRIVE_BY := 2
const STYLE_TRAIN := 3


static func attack_style(kind: int) -> int:
	match clamp_kind(kind):
		STOVEBREAKERS, ASH_WARDENS:
			return STYLE_CHARGE
		DEBT_WINGS:
			return STYLE_DRIVE_BY
		ROLLING_HEARTHS:
			return STYLE_TRAIN
		_:
			return STYLE_HOLD


static func regiment_size(kind: int, hearthline_n: int = 100) -> int:
	match clamp_kind(kind):
		HEARTHLINE:
			return clampi(hearthline_n, 1, 500)
		DEBT_WINGS:
			return 5
		STOVEBREAKERS:
			return 80
		ASH_WARDENS:
			return 60
		WALK_MAPPERS:
			return 40
		LEDGER_PIECES:
			return 8
		ROLLING_HEARTHS:
			return 3
		CEILING_CLERKS:
			return 40
		_:
			return 40


static func sprite_size(kind: int) -> float:
	match clamp_kind(kind):
		DEBT_WINGS:
			return 5.2
		LEDGER_PIECES:
			return 5.0
		ROLLING_HEARTHS:
			return 5.6
		_:
			return 3.2


static func friendly_tex(kind: int) -> String:
	match clamp_kind(kind):
		HEARTHLINE:
			return "res://assets/units/soldier_friendly_sheet.png"
		DEBT_WINGS:
			return "res://assets/units/bomber_friendly.png"
		STOVEBREAKERS:
			return "res://assets/units/hearthkin/stovebreakers_friendly_sheet.png"
		ASH_WARDENS:
			return "res://assets/units/hearthkin/ash_wardens_friendly_sheet.png"
		WALK_MAPPERS:
			return "res://assets/units/hearthkin/walk_mappers_friendly_sheet.png"
		LEDGER_PIECES:
			return "res://assets/units/hearthkin/ledger_pieces_friendly_sheet.png"
		ROLLING_HEARTHS:
			return "res://assets/units/hearthkin/rolling_hearths_friendly.png"
		CEILING_CLERKS:
			return "res://assets/units/hearthkin/ceiling_clerks_friendly_sheet.png"
		_:
			return "res://assets/units/soldier_friendly_sheet.png"


static func hostile_tex(kind: int) -> String:
	match clamp_kind(kind):
		HEARTHLINE:
			return "res://assets/units/soldier_hostile_sheet.png"
		DEBT_WINGS:
			return "res://assets/units/bomber_hostile.png"
		STOVEBREAKERS:
			return "res://assets/units/hearthkin/stovebreakers_hostile_sheet.png"
		ASH_WARDENS:
			return "res://assets/units/hearthkin/ash_wardens_hostile_sheet.png"
		WALK_MAPPERS:
			return "res://assets/units/hearthkin/walk_mappers_hostile_sheet.png"
		LEDGER_PIECES:
			return "res://assets/units/hearthkin/ledger_pieces_hostile_sheet.png"
		ROLLING_HEARTHS:
			return "res://assets/units/hearthkin/rolling_hearths_hostile.png"
		CEILING_CLERKS:
			return "res://assets/units/hearthkin/ceiling_clerks_hostile_sheet.png"
		_:
			return "res://assets/units/soldier_hostile_sheet.png"


static func tex_for(kind: int, fac: int) -> String:
	return friendly_tex(kind) if fac == 0 else hostile_tex(kind)


static func sheet_cols(kind: int) -> int:
	match clamp_kind(kind):
		LEDGER_PIECES:
			return 2
		_:
			return 8 if uses_sheet(kind) else 1


static func max_cards(kind: int) -> int:
	return 16 if is_air(kind) else 50


static func bucket_id(kind: int, fac: int) -> int:
	return clamp_kind(kind) * 2 + (fac & 1)


static func kind_of_bucket(bucket: int) -> int:
	return clampi(int(bucket) / 2, 0, COUNT - 1)
