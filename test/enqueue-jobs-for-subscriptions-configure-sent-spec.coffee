redis      = require 'fakeredis'
RedisNS    = require '@octoblu/redis-ns'
mongojs    = require 'mongojs'
uuid       = require 'uuid'
Datastore  = require 'meshblu-core-datastore'
JobManager = require 'meshblu-core-job-manager'
{beforeEach, context, describe, it} = global
{expect} = require 'chai'
EnqueueJobsForSubscriptionsConfigureSent = require '../'

describe 'EnqueueJobsForSubscriptionsConfigureSent', ->
  beforeEach (done) ->
    database = mongojs 'subscription-test', ['subscriptions']
    @datastore = new Datastore
      database: database
      collection: 'subscriptions'
    database.collection('subscriptions').remove done

  beforeEach ->
    @redisKey = uuid.v1()
    @jobManager = new JobManager
      client: new RedisNS 'ns', redis.createClient(@redisKey)
      timeoutSeconds: 1

  beforeEach ->
    client = new RedisNS 'ns', redis.createClient(@redisKey)

    @sut = new EnqueueJobsForSubscriptionsConfigureSent {
      datastore: @datastore
      jobManager: new JobManager {client: client, timeoutSeconds: 1}
      uuidAliasResolver: {resolve: (uuid, callback) -> callback(null, uuid)}
    }

  describe '->do', ->
    context 'when there are no subscriptions', ->
      context 'when given a configuration', ->
        beforeEach (done) ->
          request =
            metadata:
              responseId: 'its-electric'
              uuid: 'electric-eels'
              messageType: 'received'
              options: {}
            rawData: '{}'

          @sut.do request, (error, @response) => done error

        it 'should return a 204', ->
          expectedResponse =
            metadata:
              responseId: 'its-electric'
              code: 204
              status: 'No Content'

          expect(@response).to.deep.equal expectedResponse

    context 'when there are one subscriptions', ->
      beforeEach (done) ->
        record =
          type: 'configure.sent'
          emitterUuid: 'emitter-uuid'
          subscriberUuid: 'subscriber-uuid'

        @datastore.insert record, done

      context 'when given a configuration', ->
        beforeEach (done) ->
          request =
            metadata:
              responseId: 'its-electric'
              fromUuid: 'emitter-uuid'
              options: {}
              forwardedRoutes: []
            rawData: '{"original":"message"}'

          @sut.do request, (error, @response) => done error

        it 'should return a 204', ->
          expectedResponse =
            metadata:
              responseId: 'its-electric'
              code: 204
              status: 'No Content'

          expect(@response).to.deep.equal expectedResponse

        it 'should enqueue a job to deliver the configuration', (done) ->
          @jobManager.getRequest ['request'], (error, request) =>
            return done error if error?
            delete request.metadata.responseId
            expect(request).to.containSubset {
              metadata:
                jobType: 'DeliverSubscriptionConfigureSent'
                auth:
                  uuid: 'subscriber-uuid'
                fromUuid: 'emitter-uuid'
                toUuid: 'subscriber-uuid'
                route: [
                  {
                    from: "emitter-uuid"
                    to: "subscriber-uuid"
                    type: "configure.sent"
                  }
                ]
                forwardedRoutes: []
              rawData: '{"original":"message"}'
            }
            done()
