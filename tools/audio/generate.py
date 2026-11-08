#!/usr/bin/env python3
"""Bounded ElevenLabs authoring. API credentials never enter Flutter assets."""
import argparse, concurrent.futures, hashlib, json, os, shutil, subprocess, time, urllib.error, urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/audio'
SOUNDS={
 'select':(.5,'One very short soft tactile wooden button click for a quiz answer selection. Dry, light, rounded, instant onset, no ringing, no voice, no ambience, no melody. One click only.'),
 'correct':(.8,'One friendly quiz correct-answer cue: two clean ascending marimba notes with a soft glass accent, warm and satisfying, restrained volume, instant onset, short decay, no voice, no background noise.'),
 'wrong':(.65,'One gentle incorrect-answer cue for an educational quiz: two soft descending muted synth notes, thoughtful rather than punishing, no harsh buzzer, no alarm, no voice, dry instant onset.'),
 'tick':(.5,'One soft isolated clock tick for the final three seconds of a quiz timer. Brief rounded wooden tick, clean and precise, no alarm, no ambience, no voice, exactly one tick.'),
 'match_found':(1.2,'A short friendly competitive quiz match-found cue. A crisp soft whoosh resolving into a clean ascending three-note mallet chord. Energetic but subtle, no voice, no fanfare, clean dry sound.'),
 'question_start':(.5,'One quiet crisp question-ready cue for a learning app. A single warm plucked synth note with a soft click, immediate onset and fast decay, no voice, no ambience.'),
 'final_round':(1.1,'A short focused final-round quiz cue. Two warm low tom taps followed by a bright rising mallet note. Encouraging, controlled and brief, no tense alarm, no voice, no background music.'),
 'win':(2.0,'A short original quiz victory cue: a warm ascending major-pentatonic marimba flourish resolving to a light bell chord. Celebratory, refined and compact, no orchestra, no voice, no applause.'),
 'loss':(1.1,'A gentle end-of-round learning cue: a descending two-note warm electric piano phrase resolving calmly. Encouraging and relaxed, no sad trombone, no buzzer, no voice.'),
 'draw':(1.1,'A short balanced draw-result cue for a friendly quiz duel: two alternating clean mallet tones resolving into a warm unison chord. Calm, positive, no voice, no ambience.'),
 'level_up':(1.4,'A short original level-up reward sound for an education app: four ascending soft glass and marimba notes with a light shimmering final note. Refined and satisfying, no voice, no long tail.'),
 'timeout':(.7,'One gentle quiz timer-ended cue: a short soft wooden click followed by a low warm muted note, clear without being alarming, instant onset, no voice, no harsh buzz.')
}
MUSIC='''Original instrumental background loop for SJ E-Learning, a friendly competitive-exam quiz app. Exactly 30 seconds, 96 BPM, twelve bars of 4/4. Warm plucked marimba and soft electric piano, restrained light percussion, gentle rounded bass, sparse optimistic pentatonic motif. Focused, engaging and quietly competitive. Consistent low intensity with plenty of space for question reading and UI sound effects. Begin on a clean bar boundary and finish with a matching tonic and groove for seamless looping. No vocals, speech, lyrics, large builds, dramatic drops, harsh treble or sudden loud events.'''
def config():
 result={}
 for line in (ROOT/'.env').read_text().splitlines():
  line=line.strip()
  if not line or line.startswith('#') or '=' not in line:continue
  key,value=line.split('=',1);result[key.strip()]=value.strip().strip('"\'')
 for key in ['ELEVENLABS_API_KEY','ELEVENLABS_SFX_MODEL','ELEVENLABS_MUSIC_MODEL']:
  if os.environ.get(key):result[key]=os.environ[key]
 return result

def generate(name,cfg):
 final=OUT/(name+'.mp3')
 if final.exists() and final.stat().st_size>1000:return name,{'status':'existing','file':name+'.mp3'}
 music=name=='music'
 model=cfg.get('ELEVENLABS_MUSIC_MODEL','music_v1') if music else cfg.get('ELEVENLABS_SFX_MODEL','eleven_text_to_sound_v2')
 if music: endpoint='/v1/music';body={'prompt':MUSIC,'music_length_ms':30000,'force_instrumental':True,'model_id':model};seconds=30
 else:
  endpoint='/v1/sound-generation';seconds,prompt=SOUNDS[name];body={'text':prompt,'duration_seconds':seconds,'prompt_influence':.55,'model_id':model,'loop':False}
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
 if shutil.which('ffmpeg'):
  target=-27 if music else -19
  filters=f'loudnorm=I={target}:TP=-3:LRA=5'
  if music:filters+=',afade=t=in:d=0.08,afade=t=out:st=29.88:d=0.12'
  else:filters+=' ,silenceremove=start_periods=1:start_threshold=-48dB:start_silence=0.008,afade=t=in:d=0.005'
  result=subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(rawfile),'-af',filters,'-t',str(seconds),'-ar','44100','-ac','2' if music else '1','-codec:a','libmp3lame','-b:a','128k' if music else '96k',str(final)],capture_output=True)
  if result.returncode:raise RuntimeError(f'{name}: local audio normalization failed; raw audio saved')
 else:final.write_bytes(audio)
 return name,{'status':'generated','file':name+'.mp3','provider':'ElevenLabs','model':model,'duration_seconds':seconds,'sha256':hashlib.sha256(final.read_bytes()).hexdigest(),'generated_at_unix':int(time.time())}

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--dry-run',action='store_true');parser.add_argument('--only',choices=['cues','music','all'],default='all');args=parser.parse_args()
 names=list(SOUNDS) if args.only=='cues' else ['music'] if args.only=='music' else list(SOUNDS)+['music']
 OUT.mkdir(parents=True,exist_ok=True)
 (ROOT/'docs/audio/prompts.json').write_text(json.dumps({'cues':{k:{'duration_seconds':v[0],'prompt':v[1]} for k,v in SOUNDS.items()},'music':{'duration_seconds':30,'prompt':MUSIC}},indent=2)+'\n')
 if args.dry_run:print(f'Plan: {len([n for n in names if n!="music"])} short cues, {int("music" in names)} music loop; existing files are skipped.');return
 cfg=config()
 if not cfg.get('ELEVENLABS_API_KEY'):raise SystemExit('Set ELEVENLABS_API_KEY in the ignored .env file first.')
 manifestfile=OUT/'audio_manifest.json';manifest=json.loads(manifestfile.read_text()) if manifestfile.exists() else {}
 errors=[]
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
  jobs={pool.submit(generate,name,cfg):name for name in names}
  for job in concurrent.futures.as_completed(jobs):
   try:
    name,entry=job.result();manifest[name]={**manifest.get(name,{}),**entry};manifestfile.write_text(json.dumps(manifest,indent=2)+'\n');print(name+': '+entry['status'],flush=True)
   except Exception as error:errors.append(str(error));print(str(error),flush=True)
 if errors:raise SystemExit(f'{len(errors)} assets need attention. Successful assets were saved; reruns skip them.')
 print('Audio generation complete. Only bundled audio files are used by the app.',flush=True)
if __name__=='__main__':main()
