"""Execute the designated Sub2 CLI, adding the image tool declaration requested by the gateway.

No credentials are read, copied or printed here. The original CLI owns authentication,
HTTP transport and output decoding. Its installed file is not modified.
"""
from pathlib import Path
import base64, mimetypes, runpy
CLI = Path('C:/Users/carzy/.codex/skills/sub2-image-gen/scripts/sub2_image_gen.py')
namespace = runpy.run_path(str(CLI), run_name='sub2_image_cli')
bindings = namespace['generate'].__globals__
original_json = bindings['request_json']
original_multipart = bindings['request_multipart']
def response_request(fields, images=()):
 content = [{'type':'input_text','text':fields['prompt']}]
 for _, path in images:
  mime = mimetypes.guess_type(str(path))[0] or 'image/png'
  content.append({'type':'input_image','image_url':'data:'+mime+';base64,'+base64.b64encode(path.read_bytes()).decode('ascii')})
 tool = {'type':'image_generation','quality':fields.get('quality','high'),'size':fields.get('size','1024x1024')}
 payload = {'model':fields['model'],'input':[{'role':'user','content':content}],'tools':[tool],'tool_choice':{'type':'image_generation'}}
 response = original_json('POST','/responses',payload)
 images_out = [row['result'] for row in response.get('output',[]) if row.get('type')=='image_generation_call' and row.get('result')]
 if not images_out:
  raise SystemExit('Gateway response contained no generated image.')
 return {'data':[{'b64_json':image} for image in images_out]}
def request_json(method, endpoint, payload=None):
 if endpoint.startswith('/images/') and payload is not None: return response_request(payload)
 return original_json(method, endpoint, payload)
def request_multipart(method, endpoint, fields, images):
 return response_request(fields, images)
bindings['request_json'] = request_json
bindings['request_multipart'] = request_multipart
namespace['main']()
