# Bloc Remote Logger

### User flow

- Sign in or sign up to the panel via web or desktop app.
- Create an app and get the API key.
- Integrate the app with the bloc_remote_logger package.
- Associate custom keys with logs, e.g. user_id.
- See a list of devices that have logging enabled / See a list of blocs first as Julia suggested.
- Search for a specific device/bloc by its name or custom key, e.g. user_id.
- Enter device/bloc.
- See a list of blocs that logged something.
- See details about the bloc, e.g. name of the bloc, hash, place in the widget tree, …
- Navigate to the logger for a specific bloc.
- See a list of sessions.
- Each session has a start, end date, …
- Navigate to a session.
- See the bloc’s state over the period of time of the session.
- See the timeline and use the cursor to slide through it to see how the state of the bloc changed.
- See errors.
- …

### Technical thoughts

- Sending state diffs to reduce the network footprint.
- Dominik S. asked what should happen when state class changes (within the same bloc), e.g. from StateA to StateB where StateA and StateB have the same properties. IMHO, when displaying visual changes, should highlight the property difference only, but also indicate that the class name has changed.
- Julia asked if it would be possible to suppress logging some of the blocs? It could be possible via dart annotations, e.g. JsonSerializable or mixin?
- RemoteBlocObserver extending BlocObserver
- How to handle time? Device’s UTC is not real, i.e. it can be changed from the system settings.
    - For instance, bugfender simply relies on the device time.

### Architecture

- RemoteBlocObserver
    - constructor(apiKey)
        - create session (id, startDate, apiKey)
    - onCreate
        - create initial bloc change, from empty string to initial state
        - save bloc change in a database
    - onChange
        - create next state change, from the current state to the next state
        - save state change in a database
- Repository
    - createSession(session)
        - insert
            - sessionId
            - apiKey
            - startDate
    - saveChange(session, change)
        - insert
            - sessionId
- Models
    - StateChange
        - blocName: String, e.g. “DashboardBloc” or “DashboardCubit”
        - blocHashCode: Int, e.g. 755634292
        - date: Date, e.g. “2023-10-27T15:30:00.123456Z”
        - previousState: dynamic?
        - nextState: dynamic
        - toDiffString(): String, e.g.
            - if previousState is null, then empty string to nextState.
- Database
    - Tables:
        - SessionsTable
        - StatesChangesTable
        - EventsTable
        - ErrorsTable
    - insertSession(Session)
    - insertStateChange(stateChange)
    - insertEvent(event)
    - insertError(error)
    
    ### MVP
    
    - Save data in files.
    - Upload compressed files after app restart.