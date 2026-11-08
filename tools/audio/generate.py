#!/usr/bin/env python3
"""Bounded ElevenLabs authoring. API credentials never enter Flutter assets."""
import argparse, concurrent.futures, hashlib, json, os, shutil, subprocess, time, urllib.error, urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/audio'
SOUNDS={
 'select':(.5,'A single soft tactile UI selection tap: warm rounded wood block strike with instant clean transient, completely dry with zero reverb, natural decay finishing under 300ms, slight low-mid body around 400Hz. No click distortion, no ring, no tone, no ambience. One sound only.'),
 'correct':(.8,'A satisfying quiz correct-answer chime: a bright clear marimba note immediately followed by a warmer marimba note a perfect fifth higher, with a brief shimmering crystal bell accent blooming on the second note. Major key resolution, instant woody attack, natural resonance decaying by 800ms. Uplifting and warm. No reverb tail beyond 900ms, no voice, no background.'),
 'wrong':(1.2,'One friendly wrong-answer UI cue: two soft rounded digital mallet notes stepping down a whole tone, with a warm wooden attack and clean smooth decay. Clear, understated and gentle. Gesture finishes by 650ms, then naturally fades to silence. No Rhodes, organ, buzzer, alarm, voice or background.'),
 'tick':(.5,'A single ultra-precise dry mechanical clock tick: sharp wood block transient with peak energy at 3kHz and complete silence by 150ms. Clinical and precise, used for a final countdown. Completely dry, no reverb, no tone sustain, no ambience. One tick only.'),
 'match_found':(1.2,'A competitive online quiz match-ready alert: a quick upward digital sweep (60ms) blossoming into a clean bright three-note ascending mallet chord C-E-G with shimmering harmonics and a natural 700ms decay. Energetic and game-like, signals a live match starting. No voice, no fanfare, no bass drop.'),
 'question_start':(.5,'A single warm plucked nylon-string guitar note in the mid register, gentle fingerstyle attack with natural harmonic decay over 400ms. Calm and focused, signals a fresh new question. No chord, no vibrato, no ambience, no second note. One note only.'),
 'final_round':(1.6,'One refined final-question cue: three warm glass-marimba notes rising in a bright major triad, with a light confident lift and gentle luminous finish. Immediate onset, resolves by 900ms, natural decay and silence at the end. Focused and motivating. No drums, toms, bass impact, cinematic boom, alarm or voice.'),
 'win':(2.0,'A polished quiz victory fanfare: five bright marimba notes ascending in a major pentatonic scale (100ms per note) resolving into a sustained warm bell-resonator chord with gentle shimmer that blooms and decays to silence by 2 seconds. Celebratory, refined, compact. No orchestral swell, no applause, no voice.'),
 'loss':(1.1,'A gentle encouraging end-of-round cue: two warm descending notes on a soft Rhodes electric piano, moving down a major third, with a light natural reverb halo fading gracefully to silence by 1.1 seconds. Calm and supportive tone — not defeated. No minor-key sadness, no sad trombone, no voice.'),
 'draw':(1.1,'A balanced neutral quiz draw-result cue: two alternating soft vibraphone notes panned slightly left and right, resolving together into a warm sustained open-fifth chord with gentle decay ending by 1.1 seconds. Neither winning nor losing — stable and even. No voice, no melody, no ambience.'),
 'level_up':(1.4,'A rewarding level-up achievement sound: four rapid ascending crystal chime notes in a pentatonic scale (each 80ms, stepping higher in pitch), followed by a bright shimmering sustain of layered bell harmonics blooming and decaying over 600ms. Progressive, satisfying, earned. 1.4 seconds total. No voice, no background, no music bed.'),
 'timeout':(1.2,'One calm time-is-up UI cue: a soft clear wooden tap, then a slightly lower rounded ceramic pluck 180ms later. A friendly double knock, crisp and distinct. Complete gesture and decay by 650ms, silence at the end. No sustained note, organ, buzzer, alarm, clock ticking, voice or background.')
}
MUSIC='''A seamless 30-second instrumental background loop for a competitive mobile quiz game. 100 BPM, 4/4 time, 8 bars. Warm marimba carrying a sparse optimistic pentatonic melody in the upper register; plucked acoustic guitar providing rhythmic offbeat texture; soft rounded electric bass on root notes; light closed hi-hat and brushed snare groove. Mood: focused, quietly competitive and gently energising — engaging enough to signal a live match without distracting from reading. Dynamics remain consistently low throughout with no builds, drops or sudden peaks. Starts and ends cleanly on the tonic chord downbeat for perfect seamless playback. No vocals, no lyrics, no spoken words, no dramatic changes, no harsh treble, no sudden loud events.'''
def config():
 result={}
 for line in (ROOT/'.env').read_text().splitlines():
  line=line.strip()
  if not line or line.startswith('#') or '=' not in line:continue
  key,value=line.split('=',1);result[key.strip()]=value.strip().strip('"\'')
 for key in ['ELEVENLABS_API_KEY','ELEVENLABS_SFX_MODEL','ELEVENLABS_MUSIC_MODEL']:
  if os.environ.get(key):result[key]=os.environ[key]
 return result

def master(rawfile,final,music=False):
 if not shutil.which('ffmpeg') or not shutil.which('ffprobe'):
  raise RuntimeError('ffmpeg and ffprobe are required to preserve and finish sound tails')
 probe=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','json',str(rawfile)],capture_output=True,text=True,check=True)
 duration=float(json.loads(probe.stdout)['format']['duration'])
 filters=f'loudnorm=I={-27 if music else -19}:TP=-3:LRA=5'
 if music:filters+=f',afade=t=in:d=0.08,afade=t=out:st={max(0,duration-.12)}:d=0.12'
 else:
  # Keep the entire generated clip: no hard -t cutoff. Finish its tail quietly.
  filters+=f',afade=t=in:d=0.005,afade=t=out:st={max(0,duration-.14)}:d=0.14,apad=pad_dur=0.08'
 temporary=final.with_name('.'+final.stem+'.working.mp3')
 result=subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(rawfile),'-af',filters,'-ar','44100','-ac','2' if music else '1','-codec:a','libmp3lame','-b:a','128k' if music else '96k',str(temporary)],capture_output=True)
 if result.returncode:raise RuntimeError(f'{final.stem}: audio mastering failed; previous playable asset preserved')
 temporary.replace(final)
 return duration+(0 if music else .08)

def generate(name,cfg,replace=False):
 final=OUT/(name+'.mp3')
 if not replace and final.exists() and final.stat().st_size>1000:return name,{'status':'existing','file':name+'.mp3'}
 music=name=='music'
 model=cfg.get('ELEVENLABS_MUSIC_MODEL','music_v2_5') if music else cfg.get('ELEVENLABS_SFX_MODEL','eleven_text_to_sound_v3')
 if music: endpoint='/v1/music';body={'prompt':MUSIC,'music_length_ms':30000,'force_instrumental':True,'model_id':model};seconds=30
 else:
  endpoint='/v1/sound-generation';seconds,prompt=SOUNDS[name];body={'text':prompt,'duration_seconds':seconds,'prompt_influence':.75,'model_id':model,'loop':False}
 request=urllib.request.Request('https://api.elevenlabs.io'+endpoint+'?output_format=mp3_44100_128',data=json.dumps(body).encode(),headers={'xi-api-key':cfg['ELEVENLABS_API_KEY'],'Content-Type':'application/json'},method='POST')
 try:
  with urllib.request.urlopen(request,timeout=240) as response: audio=response.read()
 except urllib.error.HTTPError as error:
  code='request_rejected'
  try:
   detail=json.loads(error.read()).get('detail',{})
   if isinstance(detail,dict): code=str(detail.get('status',code))[:80]
  except Exception:pass
  raise RuntimeError(f'{name}: ElevenLabs HTTP {error.code} ({code}); no automatic retry') from None
 if len(audio)<1000:raise RuntimeError(f'{name}: invalid audio response')
 raw=OUT/'raw';raw.mkdir(exist_ok=True);rawfile=raw/(name+'.mp3');rawfile.write_bytes(audio)
 actual_seconds=master(rawfile,final,music)

 return name,{'status':'generated','file':name+'.mp3','provider':'ElevenLabs','model':model,'duration_seconds':round(actual_seconds,3),'requested_duration_seconds':seconds,'sha256':hashlib.sha256(final.read_bytes()).hexdigest(),'generated_at_unix':int(time.time())}

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--dry-run',action='store_true');parser.add_argument('--only',choices=['cues','music','all'],default='all');parser.add_argument('--sounds',nargs='+',choices=list(SOUNDS)+['music']);parser.add_argument('--replace',action='store_true',help='Replace only selected assets');args=parser.parse_args()
 names=args.sounds or (list(SOUNDS) if args.only=='cues' else ['music'] if args.only=='music' else list(SOUNDS)+['music'])
 OUT.mkdir(parents=True,exist_ok=True)
 (ROOT/'docs/audio/prompts.json').write_text(json.dumps({'cues':{k:{'duration_seconds':v[0],'prompt':v[1]} for k,v in SOUNDS.items()},'music':{'duration_seconds':30,'prompt':MUSIC}},indent=2)+'\n')
 if args.dry_run:print(f'Plan: {len([n for n in names if n!="music"])} short cues, {int("music" in names)} music loop; existing files are replaced only with --replace.');return
 cfg=config()
 if not cfg.get('ELEVENLABS_API_KEY'):raise SystemExit('Set ELEVENLABS_API_KEY in the ignored .env file first.')
 manifestfile=OUT/'audio_manifest.json';manifest=json.loads(manifestfile.read_text()) if manifestfile.exists() else {}
 errors=[]
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
  jobs={pool.submit(generate,name,cfg,args.replace):name for name in names}
  for job in concurrent.futures.as_completed(jobs):
   try:
    name,entry=job.result();manifest[name]={**manifest.get(name,{}),**entry};manifestfile.write_text(json.dumps(manifest,indent=2)+'\n');print(name+': '+entry['status'],flush=True)
   except Exception as error:errors.append(str(error));print(str(error),flush=True)
 if errors:raise SystemExit(f'{len(errors)} assets need attention. Successful assets were saved; reruns skip them.')
 print('Audio generation complete. Only bundled audio files are used by the app.',flush=True)
if __name__=='__main__':main()
