_                   = require 'lodash'
async               = require 'async'
http                = require 'http'
SubscriptionManager = require 'meshblu-core-manager-subscription'

class EnqueueJobsForSubscriptionsConfigureSent
  constructor: ({datastore,@jobManager,uuidAliasResolver}) ->
    @subscriptionManager ?= new SubscriptionManager {datastore, uuidAliasResolver}

  _doCallback: (request, code, callback) =>
    response =
      metadata:
        responseId: request.metadata.responseId
        code: code
        status: http.STATUS_CODES[code]
    callback null, response

  do: (request, callback) =>
    {fromUuid} = request.metadata
    @subscriptionManager.emitterListForType {emitterUuid: fromUuid, type: 'configure.sent'}, (error, subscriptions) =>
      return callback error if error?
      return @_doCallback request, 204, callback if _.isEmpty subscriptions

      requests = _.map subscriptions, (subscription) =>
        @_buildRequest {request, subscription}

      async.each requests, @_createRequest, (error) =>
        return callback error if error?
        return @_doCallback request, 204, callback

  _buildRequest: ({request, subscription}) =>
    return {
      metadata:
        jobType: 'DeliverSubscriptionConfigureSent'
        auth:
          uuid: subscription.subscriberUuid
        fromUuid: subscription.emitterUuid
        toUuid: subscription.subscriberUuid
        route: [{
          from: subscription.emitterUuid
          to: subscription.subscriberUuid
          type: 'configure.sent'
        }]
        forwardedRoutes: request.metadata?.forwardedRoutes
      rawData: request.rawData
    }

  _createRequest: (request, callback) =>
    @jobManager.createRequest 'request', request, callback

module.exports = EnqueueJobsForSubscriptionsConfigureSent
