const coverage = {
  football: `Selected sport: American football. Program means football play-by-play,
replays, down/distance/clock/score analysis, football interviews, and studio or
halftime analysis. Halftime editorial discussion is program even without live play.
Fight introductions, rounds, and fighter analysis do not establish a football
return. Do not invent football commentary because football was selected.`,
  ufc: `Selected sport: UFC/MMA. Program means fighting, replays, walkouts, fighter
introductions, corner discussion, round/score analysis, decisions, interviews,
and between-fight editorial coverage. An end of round is not itself a break.
Football play-by-play does not establish a UFC return. Do not invent fight
commentary because UFC was selected.`
};

export function sportPrompt(shared, sport) {
  if (!Object.hasOwn(coverage, sport)) throw new Error('Invalid sport selection');
  return `${coverage[sport]}\n\n${shared}`;
}
