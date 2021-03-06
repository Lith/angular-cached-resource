describe 'CachedResource.post', ->
  {CachedResource, $httpBackend, $timeout, $log} = {}

  beforeEach ->
    inject ($injector) ->
      $cachedResource = $injector.get '$cachedResource'
      $httpBackend = $injector.get '$httpBackend'
      $timeout = $injector.get '$timeout'
      $log = $injector.get '$log'
      CachedResource = $cachedResource 'class-save-test', '/mock/:id'
    $log.reset()

  describe 'while online', ->
    it 'saves the resource normally', (done) ->
      $httpBackend.expectPOST('/mock/1', magic: 'This is a saved resource').respond
        id: 1
        magic: 'Here is the response'
      resource = CachedResource.save {id: 1}, {magic: 'This is a saved resource'}
      resource.$promise.then ->
        expect(resource.magic).to.equal 'Here is the response'
        done()
      $httpBackend.flush()

  describe 'when server is not reachable', ->

    {resource} = {}

    beforeEach ->
      $httpBackend.expectPOST('/mock/1', magic: 'Save #1').respond 504
      resource = CachedResource.save {id: 1}, {magic: 'Save #1'}
      $httpBackend.flush()

    it 'attempts the save again when a window.onOnline event is sent', ->
      $httpBackend.expectPOST('/mock/1', magic: 'Save #1').respond 200

      # https://developer.mozilla.org/en-US/docs/Web/API/document.createEvent
      # says that this is deprecated, but it also seems to be the only way to
      # create a custom event using PhantomJS, which we use to run these tests
      event = document.createEvent 'CustomEvent'
      event.initEvent 'online', true, true

      document.dispatchEvent event

      $httpBackend.flush()

    it 'attempts the save again after a timeout has passed', ->
      $httpBackend.expectPOST('/mock/1', magic: 'Save #1').respond 200
      $timeout.flush()
      $httpBackend.flush()

    it 'attempts the save a third time after another timeout has passed, if the first timeout save failed', ->
      $httpBackend.expectPOST('/mock/1', magic: 'Save #1').respond 504
      $timeout.flush()
      $httpBackend.flush()

      $httpBackend.expectPOST('/mock/1', magic: 'Save #1').respond 200
      $timeout.flush()
      $httpBackend.flush()

    it 'caches the write in localStorage so the write happens when the page refreshes, too', ->
      cachedWriteString = localStorage.getItem 'cachedResource://class-save-test/write'
      expect(cachedWriteString).to.exist
      cachedWrite = angular.fromJson cachedWriteString
      expect(cachedWrite).to.have.length 1
      expect(cachedWrite).to.have.deep.property '[0].action', 'save'
      expect(cachedWrite).to.have.deep.property '[0].params.id', 1

  describe 'when server returns 400', ->

    beforeEach ->
      $httpBackend.expectPOST('/mock/1', magic: 'Save #1').respond 400
      resource = CachedResource.save {id: 1}, {magic: 'Save #1'}
      $httpBackend.flush()

    it 'stops trying to save the resource', ->
      expect(CachedResource.$writes.queue.length).to.equal 0

    it 'logs the failed write to $logger.error', ->
      expect($log.error.logs.length).to.equal 1
      expect($log.error.logs[0][0]).to.equal 'ngCachedResource'
      expect($log.error.logs[0][1]).to.contain 'save to class-save-test'
      expect($log.error.logs[0][1]).to.contain 'failed with error 400'
      expect($log.error.logs[0][2]).to.have.property 'method', 'POST'
      expect($log.error.logs[0][2]).to.have.property 'url', '/mock/1'
      expect($log.error.logs[0][2]).to.have.property 'writeData'
