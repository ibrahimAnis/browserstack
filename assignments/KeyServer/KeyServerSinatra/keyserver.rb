'''
Key Server problem:
Write a server which can generate random api keys, assign them for usage and 
release them after sometime.

Following endpoints should be available on the server to interact with it.
See notes just before each endpoint.

Apart from these endpoints, following rules should be enforced:
See rule at endpoint e3

No endpoint call should result in an iteration of whole set of keys i.e. 
no endpoint request should be O(n). They should either be O(lg n) or O(1).
'''

require 'sinatra'
require 'redis'
require 'json'
require 'securerandom'

$redis = Redis.new
$redis.set("available", Array.new())

#  E1. There should be one endpoint to generate keys.
get '/e1' do
  id = SecureRandom.hex(4)
  key = Hash.new()
  key["id"] = id
  key["keep_alive_timestamp"] = Time.now
  key["is_blocked"] = false
  key["blocked_timestamp"] = nil
  key["is_dead"] = false
  $redis.set(id.to_s, key.to_json)
  available = JSON.parse($redis.get("available"))
  available.push(id)
  $redis.set("available", available)
  [201]
end

#E2. There should be an endpoint to get an available key. 
#    On hitting this endpoint server should serve a random key which is not already being used.
#    This key should be blocked and should not be served again by E2, till it is in this state
#    If no eligible key is available then it should serve 404.
get '/e2' do
  available = JSON.parse($redis.get("available"))
  id = available.shift
  $redis.set("available", available)
  if id != nil
    key = JSON.parse($redis.get(id.to_s))
    if !key["is_dead"]
      key["is_blocked"] = true
      key["blocked_timestamp"] = Time.now
      $redis.set(id.to_s, key.to_json)
      [200, id]
    end
  else
    [404]
  end
end

#E3. There should be an endpoint to unblock a key. 
#    Unblocked keys can be served via E2 again.
# R1. All blocked keys should get released automatically within 60 secs if E3 is not called.
get '/e3/:id' do
  id = params['id']
  key = JSON.parse($redis.get(id.to_s))
  key["is_blocked"] = false
  key["blocked_timestamp"] = nil
  $redis.set(id.to_s, key.to_json)
  available = JSON.parse($redis.get("available"))
  available.push(id)
  $redis.set("available", available)
  # TODO: fire delayed_job to release a key after 60 secs
  [200]
end

#E4. There should be an endpoint to delete a key. 
#    Deleted keys should be purged.
delete '/e4/:id' do
  id = params['id']
  key = JSON.parse($redis.get(id.to_s))
  key["is_dead"] = true
  $redis.set(id.to_s, key.to_json)
  $redis.del(id.to_s)
  [200]
end

#E5. All keys are to be kept alive by clients calling this endpoint every 5 minutes.
#    If a particular key has not received a keep alive in last five minutes then it should
#    be deleted and never used again.
put '/e5/:id' do
  id = params['id']
  if $redis.exists(id.to_s)
    key = JSON.parse($redis.get(id.to_s))
    key["keep_alive"] = Time.now
    $redis.set(id.to_s, key.to_json)
    [200]
  else
    [404]
  end
  # TODO: fire delayed_job to delete key after 5 mins
end