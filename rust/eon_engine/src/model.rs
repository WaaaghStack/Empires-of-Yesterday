//! Narrow, normalized authority tables + tunable config.
//!
//! This is the *authority* state for the World scope. Per the transaction-engine contract, the
//! hard work happens as ordered transactions over these narrow tables; wide denormalized rows
//! live only in the report/replay layer (`crate::turn::TurnReport`, `crate::battle::BattleReport`).

pub type FactionId = u32;
pub type ProvinceId = u32;
pub type ArmyId = u32;
pub type AgentId = u32;

/// Magic gem paths — the strategic minerals reinterpreted as Dominions-style paths.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[repr(u16)]
pub enum GemPath {
    Aurelium = 0,
    Verdantite = 1,
    Emberstone = 2,
}

impl GemPath {
    pub fn all() -> [GemPath; 3] {
        [GemPath::Aurelium, GemPath::Verdantite, GemPath::Emberstone]
    }
    pub fn as_str(self) -> &'static str {
        match self {
            GemPath::Aurelium => "aurelium",
            GemPath::Verdantite => "verdantite",
            GemPath::Emberstone => "emberstone",
        }
    }
}

/// Locomotion domain. One battle loop; kinds pick a plane (ground / air / sea).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UnitDomain {
    Land,
    Air,
    Naval,
}

/// How a land/air body behaves once it has a target. Closed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AttackStyle {
    /// Get to weapon reach, halt, fire. Do not walk into the scrum.
    Hold,
    /// Close into contact and stay in the fight.
    Charge,
    /// Overfly, pickle, continue the pass, come around.
    DriveBy,
    /// Stay in the train. No charge, no gun-walk.
    Train,
}

/// Campaign unit kinds. 0/1 stay Hearthline / Debt Wings. 2–7 are Compact jobs.
/// KindProfile: hp, attack, attack_interval, reach, perception, speed, cohesion,
/// vs_air, blast, cruise_z, regiment_size, spacing, plus closed `group`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UnitKind {
    Soldier = 0,
    Bomber = 1,
    Stovebreaker = 2,
    AshWarden = 3,
    WalkMapper = 4,
    LedgerPiece = 5,
    RollingHearth = 6,
    CeilingClerk = 7,
}

impl UnitKind {
    pub const ALL: [UnitKind; 8] = [
        UnitKind::Soldier,
        UnitKind::Bomber,
        UnitKind::Stovebreaker,
        UnitKind::AshWarden,
        UnitKind::WalkMapper,
        UnitKind::LedgerPiece,
        UnitKind::RollingHearth,
        UnitKind::CeilingClerk,
    ];

    pub fn from_u8(v: u8) -> Self {
        match v {
            1 => UnitKind::Bomber,
            2 => UnitKind::Stovebreaker,
            3 => UnitKind::AshWarden,
            4 => UnitKind::WalkMapper,
            5 => UnitKind::LedgerPiece,
            6 => UnitKind::RollingHearth,
            7 => UnitKind::CeilingClerk,
            _ => UnitKind::Soldier,
        }
    }
    pub fn as_u8(self) -> u8 {
        self as u8
    }
    pub fn as_str(self) -> &'static str {
        match self {
            UnitKind::Soldier => "soldier",
            UnitKind::Bomber => "bomber",
            UnitKind::Stovebreaker => "stovebreaker",
            UnitKind::AshWarden => "ash_warden",
            UnitKind::WalkMapper => "walk_mapper",
            UnitKind::LedgerPiece => "ledger_piece",
            UnitKind::RollingHearth => "rolling_hearth",
            UnitKind::CeilingClerk => "ceiling_clerk",
        }
    }
    pub fn domain(self) -> UnitDomain {
        match self {
            UnitKind::Bomber => UnitDomain::Air,
            _ => UnitDomain::Land,
        }
    }
    /// 0 = ignore the formation guide (swarm); 1 = glued to slot (armor).
    pub fn cohesion(self) -> f32 {
        match self {
            UnitKind::Soldier => 0.42,
            UnitKind::Bomber => 0.22,
            UnitKind::Stovebreaker => 0.70,
            UnitKind::AshWarden => 0.50,
            UnitKind::WalkMapper => 0.25,
            UnitKind::LedgerPiece => 0.35,
            UnitKind::RollingHearth => 0.55,
            UnitKind::CeilingClerk => 0.45,
        }
    }
    /// How far a body looks for someone to fight (guide does not pick this target).
    /// Must be at least weapon reach or they cannot shoot the range they have.
    pub fn perception(self) -> f32 {
        match self {
            UnitKind::Soldier => 70.0,
            UnitKind::Bomber => 48.0,
            UnitKind::Stovebreaker => 36.0,
            UnitKind::AshWarden => 40.0,
            UnitKind::WalkMapper => 90.0,
            UnitKind::LedgerPiece => 160.0,
            UnitKind::RollingHearth => 24.0,
            UnitKind::CeilingClerk => 90.0,
        }
    }
    pub fn base_hp(self) -> f32 {
        match self {
            UnitKind::Soldier => 100.0,
            UnitKind::Bomber => 540.0,
            UnitKind::Stovebreaker => 140.0,
            UnitKind::AshWarden => 100.0,
            UnitKind::WalkMapper => 70.0,
            UnitKind::LedgerPiece => 80.0,
            UnitKind::RollingHearth => 220.0,
            UnitKind::CeilingClerk => 90.0,
        }
    }
    pub fn base_attack(self) -> f32 {
        match self {
            UnitKind::Soldier => 12.0,
            UnitKind::Bomber => 55.0,
            UnitKind::Stovebreaker => 16.0,
            UnitKind::AshWarden => 8.0,
            UnitKind::WalkMapper => 8.0,
            UnitKind::LedgerPiece => 40.0,
            UnitKind::RollingHearth => 4.0,
            UnitKind::CeilingClerk => 10.0,
        }
    }
    /// Weapon reach — must be long enough to shoot across the engagement gap.
    pub fn reach(self) -> f32 {
        match self {
            UnitKind::Soldier => 70.0,
            UnitKind::Bomber => 18.0,
            UnitKind::Stovebreaker => 22.0,
            UnitKind::AshWarden => 18.0,
            UnitKind::WalkMapper => 40.0,
            UnitKind::LedgerPiece => 160.0,
            UnitKind::RollingHearth => 8.0,
            UnitKind::CeilingClerk => 80.0,
        }
    }
    /// Small-arms vs aircraft. ~50 infantry should bring one bomber down; a handful should not.
    pub fn vs_air(self) -> f32 {
        match self {
            UnitKind::Soldier => 0.08,
            UnitKind::Bomber => 1.0,
            UnitKind::Stovebreaker => 0.04,
            UnitKind::AshWarden => 0.05,
            UnitKind::WalkMapper => 0.06,
            UnitKind::LedgerPiece => 0.02,
            UnitKind::RollingHearth => 0.02,
            UnitKind::CeilingClerk => 1.4,
        }
    }
    /// Ground blast radius. Zero = single-target (rifle).
    pub fn blast_radius(self) -> f32 {
        match self {
            UnitKind::Soldier => 0.0,
            UnitKind::Bomber => 12.0,
            UnitKind::Stovebreaker => 0.0,
            UnitKind::AshWarden => 4.0,
            UnitKind::WalkMapper => 0.0,
            UnitKind::LedgerPiece => 16.0,
            UnitKind::RollingHearth => 0.0,
            UnitKind::CeilingClerk => 0.0,
        }
    }
    pub fn move_speed(self) -> f32 {
        match self {
            UnitKind::Soldier => 2.4,
            UnitKind::Bomber => 4.2,
            UnitKind::Stovebreaker => 2.0,
            UnitKind::AshWarden => 2.2,
            UnitKind::WalkMapper => 3.2,
            UnitKind::LedgerPiece => 1.4,
            UnitKind::RollingHearth => 1.6,
            UnitKind::CeilingClerk => 2.3,
        }
    }
    pub fn cruise_z(self) -> f32 {
        match self {
            UnitKind::Bomber => 14.0,
            _ => 0.0,
        }
    }
    /// Total War-style regiment size (bodies per distinct unit on the field).
    pub fn regiment_size(self) -> u32 {
        match self {
            UnitKind::Soldier => 100,
            UnitKind::Bomber => 5,
            UnitKind::Stovebreaker => 80,
            UnitKind::AshWarden => 60,
            UnitKind::WalkMapper => 40,
            UnitKind::LedgerPiece => 8,
            UnitKind::RollingHearth => 3,
            UnitKind::CeilingClerk => 40,
        }
    }
    /// Battle ticks between shots. Hearthline 3 is today's land cadence;
    /// Debt Wings 32 is today's bomb floor. Viewer records every `RECORD_STRIDE` ticks.
    pub fn attack_interval(self) -> u32 {
        match self {
            UnitKind::Soldier => 3,
            UnitKind::Bomber => 32,
            UnitKind::Stovebreaker => 2,
            UnitKind::AshWarden => 6,
            UnitKind::WalkMapper => 4,
            UnitKind::LedgerPiece => 8,
            UnitKind::RollingHearth => 16,
            UnitKind::CeilingClerk => 4,
        }
    }
    /// How a body behaves once it has a target. Closed. Combat authority only.
    pub fn attack_style(self) -> AttackStyle {
        match self {
            UnitKind::Bomber => AttackStyle::DriveBy,
            UnitKind::Stovebreaker | UnitKind::AshWarden => AttackStyle::Charge,
            UnitKind::RollingHearth => AttackStyle::Train,
            _ => AttackStyle::Hold,
        }
    }
    /// Charge closes to this; Hold halts at `reach`.
    pub fn contact_range(self) -> f32 {
        match self.attack_style() {
            AttackStyle::Charge => 6.5,
            AttackStyle::Hold => self.reach(),
            AttackStyle::Train => 0.0,
            AttackStyle::DriveBy => self.reach(),
        }
    }
    /// Parent classification for formation / placement. Closed vocab; not a second combat dialect.
    pub fn group(self) -> &'static str {
        match self {
            UnitKind::Soldier => "infantry_hybrid",
            UnitKind::Bomber => "air",
            UnitKind::Stovebreaker => "infantry_melee",
            UnitKind::AshWarden => "infantry_engineer",
            UnitKind::WalkMapper => "infantry_skirmish",
            UnitKind::LedgerPiece => "artillery",
            UnitKind::RollingHearth => "support",
            UnitKind::CeilingClerk => "anti_air",
        }
    }
    /// Center-to-center personal space. A hair wider than the HD-2D billboard
    /// (soldiers 3.2, bombers 5.2) so files don't sit in the same dirt.
    pub fn spacing(self) -> f32 {
        match self {
            UnitKind::Soldier => 3.6,
            UnitKind::Bomber => 6.4,
            UnitKind::Stovebreaker => 4.0,
            UnitKind::AshWarden => 3.8,
            UnitKind::WalkMapper => 4.2,
            UnitKind::LedgerPiece => 8.0,
            UnitKind::RollingHearth => 10.0,
            UnitKind::CeilingClerk => 3.8,
        }
    }
}

/// Total-War-style meta agents. The primary player skill lever (battles are hands-off).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AgentKind {
    Prophet,  // strong mobile dominion amplifier
    Priest,   // weaker mobile dominion amplifier
    Spy,      // sap enemy dominion + raise unrest
    Assassin, // remove enemy agents
    Diplomat, // shift relations
    Scout,    // reveal / find deposits (sets flags)
}

impl AgentKind {
    pub fn as_str(self) -> &'static str {
        match self {
            AgentKind::Prophet => "prophet",
            AgentKind::Priest => "priest",
            AgentKind::Spy => "spy",
            AgentKind::Assassin => "assassin",
            AgentKind::Diplomat => "diplomat",
            AgentKind::Scout => "scout",
        }
    }
}

#[derive(Clone, Debug)]
pub struct Faction {
    pub id: FactionId,
    pub name: String,
    pub is_ai: bool,
    pub alive: bool,
    pub ascension_points: u32,
}

/// A regiment carried by an army on the campaign map; expands into individual units in battle.
#[derive(Clone, Debug)]
pub struct Squad {
    pub kind: UnitKind,
    pub count: u32,
}

impl Squad {
    /// Split a blob count into Total War-style units (100 infantry, 5 bombers, remainder last).
    pub fn into_regiments(self) -> Vec<Squad> {
        let size = self.kind.regiment_size().max(1);
        let mut left = self.count;
        let mut out = Vec::new();
        while left > 0 {
            let n = left.min(size);
            out.push(Squad { kind: self.kind, count: n });
            left -= n;
        }
        out
    }
}

#[derive(Clone, Debug)]
pub struct Army {
    pub id: ArmyId,
    pub faction: FactionId,
    pub province: ProvinceId,
    pub squads: Vec<Squad>,
    /// Movement order for the turn (set by orders/AI); resolved in the Movement phase.
    pub move_to: Option<ProvinceId>,
}

impl Army {
    pub fn total_units(&self) -> u32 {
        self.squads.iter().map(|s| s.count).sum()
    }
    pub fn is_empty(&self) -> bool {
        self.total_units() == 0
    }
}

#[derive(Clone, Debug)]
pub struct Agent {
    pub id: AgentId,
    pub faction: FactionId,
    pub province: ProvinceId,
    pub kind: AgentKind,
    pub level: u8,
    pub alive: bool,
    /// Optional per-turn action target province (spy/assassin/diplomat/scout).
    pub target: Option<ProvinceId>,
    pub move_to: Option<ProvinceId>,
}

#[derive(Clone, Debug)]
pub struct Province {
    pub id: ProvinceId,
    pub name: String,
    pub is_land: bool,
    /// Terrain elevation 0..100. **Ignored by dominion diffusion** (height-independent tide);
    /// still meaningful for battle terrain / movement (see design lock change).
    pub elevation: u8,
    pub neighbors: Vec<ProvinceId>,
    /// Per-faction dominion mass (length == faction count). The visible "faith tide".
    pub dom: Vec<f32>,
    pub unrest: f32,
    /// A built temple acts as a fixed dominion amplifier for its owner.
    pub temple_owner: Option<FactionId>,
    /// Faction whose capital sits here (strongest fixed source).
    pub capital_of: Option<FactionId>,
    pub has_throne: bool,
    pub deposit: Option<GemPath>,
    pub revealed: bool,
}

impl Province {
    /// Current owner by dominion majority, or None if neutral/contested-below-threshold.
    pub fn owner(&self, cfg: &Config) -> Option<FactionId> {
        if !self.is_land {
            return None;
        }
        let mut best: Option<(FactionId, f32)> = None;
        let mut second = 0.0f32;
        for (fid, &d) in self.dom.iter().enumerate() {
            match best {
                Some((_, bd)) if d > bd => {
                    second = bd;
                    best = Some((fid as FactionId, d));
                }
                Some((_, _)) => {
                    if d > second {
                        second = d;
                    }
                }
                None => best = Some((fid as FactionId, d)),
            }
        }
        match best {
            Some((fid, bd)) if bd >= cfg.owner_min_dominion && bd > second + 1e-4 => Some(fid),
            _ => None,
        }
    }
}

/// Tunable engine constants. Slow dominion + turn cadence is the "creep" identity.
#[derive(Clone, Debug)]
pub struct Config {
    pub dominion_spread_rate: f32,
    pub cancel_rate: f32,
    pub owner_min_dominion: f32,
    pub capital_output: f32,
    pub temple_output: f32,
    pub prophet_output: f32,
    pub priest_output: f32,
    pub spy_sap: f32,
    pub spy_unrest: f32,
    pub assassin_base_chance: f32,
    pub unrest_from_enemy: f32,
    pub unrest_decay: f32,
    pub unrest_threshold: f32,
    pub unrest_faith_erosion: f32,
    pub gem_per_deposit: f32,
    pub thrones_to_win: u32,
    pub dominion_alive_eps: f32,
    /// Hard turn cap; at this turn the leader (most land, then dominion) wins by score. Guarantees
    /// a decisive outcome even on large, symmetric maps that would otherwise stalemate.
    pub turn_limit: u32,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            dominion_spread_rate: 0.06, // slow tide
            cancel_rate: 0.35,
            owner_min_dominion: 1.0,
            capital_output: 6.0,
            temple_output: 3.0,
            prophet_output: 5.0,
            priest_output: 3.0,
            spy_sap: 4.0,
            spy_unrest: 3.0,
            assassin_base_chance: 0.5,
            unrest_from_enemy: 0.02,
            unrest_decay: 0.1,
            unrest_threshold: 5.0,
            unrest_faith_erosion: 0.5,
            gem_per_deposit: 2.0,
            thrones_to_win: 2,
            dominion_alive_eps: 0.5,
            turn_limit: 120,
        }
    }
}

/// The World authority state.
#[derive(Clone, Debug)]
pub struct World {
    pub seed: u64,
    pub turn: u32,
    pub cfg: Config,
    pub factions: Vec<Faction>,
    pub provinces: Vec<Province>,
    pub armies: Vec<Army>,
    pub agents: Vec<Agent>,
    /// Relations matrix [a][b] in [-100, 100]; symmetric by convention.
    pub relations: Vec<Vec<i16>>,
    pub next_army_id: ArmyId,
    pub next_agent_id: AgentId,
}

impl World {
    pub fn faction_count(&self) -> usize {
        self.factions.len()
    }

    pub fn province(&self, id: ProvinceId) -> &Province {
        &self.provinces[id as usize]
    }

    /// Sum of a faction's dominion across all provinces (the ledger reconciliation target).
    pub fn total_dominion(&self, f: FactionId) -> f32 {
        self.provinces.iter().map(|p| p.dom[f as usize]).sum()
    }

    /// Count of land provinces a faction owns.
    pub fn owned_land(&self, f: FactionId) -> usize {
        self.provinces
            .iter()
            .filter(|p| p.owner(&self.cfg) == Some(f))
            .count()
    }

    pub fn land_count(&self) -> usize {
        self.provinces.iter().filter(|p| p.is_land).count()
    }

    /// Owned thrones for a faction.
    pub fn owned_thrones(&self, f: FactionId) -> u32 {
        self.provinces
            .iter()
            .filter(|p| p.has_throne && p.owner(&self.cfg) == Some(f))
            .count() as u32
    }

    /// Deterministic world-state digest (proves turn replay determinism).
    pub fn digest(&self) -> u64 {
        let mut h: u64 = 0xcbf2_9ce4_8422_2325;
        let mut mix = |x: u64| {
            h ^= x;
            h = h.wrapping_mul(0x0000_0100_0000_01B3);
        };
        mix(self.turn as u64);
        for p in &self.provinces {
            mix(p.id as u64);
            mix((p.unrest * 1000.0).round() as i64 as u64);
            for d in &p.dom {
                mix((*d * 1000.0).round() as i64 as u64);
            }
            mix(p.owner(&self.cfg).map(|f| f as u64 + 1).unwrap_or(0));
        }
        for a in &self.armies {
            mix(a.id as u64);
            mix(a.faction as u64);
            mix(a.province as u64);
            mix(a.total_units() as u64);
        }
        for ag in &self.agents {
            mix(ag.id as u64);
            mix(ag.alive as u64);
            mix(ag.province as u64);
        }
        for f in &self.factions {
            mix(f.alive as u64);
            mix(f.ascension_points as u64);
        }
        h
    }
}

#[cfg(test)]
mod kind_tests {
    use super::UnitKind;

    #[test]
    fn compact_kind_ids_stay_stable() {
        assert_eq!(UnitKind::Soldier.as_u8(), 0);
        assert_eq!(UnitKind::Bomber.as_u8(), 1);
        assert_eq!(UnitKind::Stovebreaker.as_u8(), 2);
        assert_eq!(UnitKind::AshWarden.as_u8(), 3);
        assert_eq!(UnitKind::WalkMapper.as_u8(), 4);
        assert_eq!(UnitKind::LedgerPiece.as_u8(), 5);
        assert_eq!(UnitKind::RollingHearth.as_u8(), 6);
        assert_eq!(UnitKind::CeilingClerk.as_u8(), 7);
        for v in 0u8..=7 {
            assert_eq!(UnitKind::from_u8(v).as_u8(), v);
        }
        assert_eq!(UnitKind::from_u8(99), UnitKind::Soldier);
    }

    #[test]
    fn compact_profiles_can_see_their_reach() {
        let kinds = [
            UnitKind::Soldier,
            UnitKind::Bomber,
            UnitKind::Stovebreaker,
            UnitKind::AshWarden,
            UnitKind::WalkMapper,
            UnitKind::LedgerPiece,
            UnitKind::RollingHearth,
            UnitKind::CeilingClerk,
        ];
        for k in kinds {
            assert!(
                k.perception() + 0.01 >= k.reach(),
                "{} perception {} < reach {}",
                k.as_str(),
                k.perception(),
                k.reach()
            );
        }
        assert_eq!(UnitKind::LedgerPiece.perception(), 160.0);
        assert_eq!(UnitKind::LedgerPiece.blast_radius(), 16.0);
        assert_eq!(UnitKind::AshWarden.blast_radius(), 4.0);
        assert!((UnitKind::CeilingClerk.vs_air() - 1.4).abs() < 0.001);
        assert_eq!(UnitKind::Soldier.regiment_size(), 100);
        assert_eq!(UnitKind::Bomber.regiment_size(), 5);
        assert!((UnitKind::Soldier.vs_air() - 0.08).abs() < 0.001);
    }

    #[test]
    fn attack_interval_stove_faster_than_line_than_guns() {
        assert_eq!(UnitKind::Soldier.attack_interval(), 3);
        assert_eq!(UnitKind::Bomber.attack_interval(), 32);
        assert!(UnitKind::Stovebreaker.attack_interval() < UnitKind::Soldier.attack_interval());
        assert!(UnitKind::Soldier.attack_interval() < UnitKind::LedgerPiece.attack_interval());
        assert!(UnitKind::LedgerPiece.attack_interval() < UnitKind::Bomber.attack_interval());
        assert!(UnitKind::RollingHearth.attack_interval() > UnitKind::Soldier.attack_interval());
        assert!(UnitKind::WalkMapper.attack_interval() > UnitKind::Soldier.attack_interval());
        assert!(UnitKind::AshWarden.attack_interval() > UnitKind::Soldier.attack_interval());
    }

    #[test]
    fn compact_groups_match_closed_vocab() {
        assert_eq!(UnitKind::Soldier.group(), "infantry_hybrid");
        assert_eq!(UnitKind::Stovebreaker.group(), "infantry_melee");
        assert_eq!(UnitKind::WalkMapper.group(), "infantry_skirmish");
        assert_eq!(UnitKind::AshWarden.group(), "infantry_engineer");
        assert_eq!(UnitKind::CeilingClerk.group(), "anti_air");
        assert_eq!(UnitKind::LedgerPiece.group(), "artillery");
        assert_eq!(UnitKind::RollingHearth.group(), "support");
        assert_eq!(UnitKind::Bomber.group(), "air");
    }

    #[test]
    fn compact_attack_styles_match_closed_vocab() {
        use super::AttackStyle;
        assert_eq!(UnitKind::Soldier.attack_style(), AttackStyle::Hold);
        assert_eq!(UnitKind::WalkMapper.attack_style(), AttackStyle::Hold);
        assert_eq!(UnitKind::LedgerPiece.attack_style(), AttackStyle::Hold);
        assert_eq!(UnitKind::CeilingClerk.attack_style(), AttackStyle::Hold);
        assert_eq!(UnitKind::Stovebreaker.attack_style(), AttackStyle::Charge);
        assert_eq!(UnitKind::AshWarden.attack_style(), AttackStyle::Charge);
        assert_eq!(UnitKind::Bomber.attack_style(), AttackStyle::DriveBy);
        assert_eq!(UnitKind::RollingHearth.attack_style(), AttackStyle::Train);
        assert!(UnitKind::Stovebreaker.contact_range() < UnitKind::Stovebreaker.reach());
        assert_eq!(
            UnitKind::LedgerPiece.contact_range(),
            UnitKind::LedgerPiece.reach()
        );
    }
}
