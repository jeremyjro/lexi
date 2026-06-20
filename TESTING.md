# Testing Guide for Cursor Assistant

## Pre-Testing Setup

1. **Set up environment variables:**
   ```bash
   export ANTHROPIC_API_KEY="your-actual-api-key-here"
   ```

2. **Build the project:**
   ```bash
   cd /Volumes/T7/Projects/Jeremy/CursorAssistant
   swift build
   ```

3. **Grant Accessibility Permissions:**
   - Open System Preferences → Privacy & Security → Accessibility
   - Add CursorAssistant (or Terminal/Swift if running from command line)
   - Restart the application

## Testing Scenarios

### 1. Basic Functionality Test
**Goal:** Verify the core workflow works

**Steps:**
1. Run the application: `swift run CursorAssistant`
2. Open any text-based application (Safari, Pages, Notes, etc.)
3. Hold the Function key
4. Highlight a word or phrase
5. Release the Function key
6. Verify the bubble appears with an explanation

**Expected Result:**
- Bubble appears near the cursor
- Loading state shows briefly
- Explanation appears within 2-3 seconds
- Bubble is animated and smooth

### 2. Cross-Application Testing
**Goal:** Test accessibility API works across different apps

**Test Applications:**
- [ ] Safari (web pages)
- [ ] Chrome (web pages)
- [ ] Notes.app
- [ ] Pages.app
- [ ] TextEdit
- [ ] PDF in Preview
- [ ] Slack
- [ ] VS Code
- [ ] Terminal

**Steps:**
For each application:
1. Open the application
2. Open a document/page with text
3. Hold Function key + highlight text
4. Release and verify bubble appears

**Expected Result:**
- Works consistently across all text-based applications
- Context is correctly extracted from each app

### 3. Learning Style Testing
**Goal:** Verify different learning styles produce different explanations

**Steps:**
1. Modify `learningStyle` in `main.swift` to test each style:
   - `.analogies`
   - `.examples`
   - `.technical`
   - `.simple`
   - `.visual`

2. For each style, test with the same term in the same context

**Expected Result:**
- Each style produces a distinctly different explanation
- Explanations match the style's characteristics
- All explanations are under 75 words

### 4. Context Awareness Testing
**Goal:** Verify context extraction works correctly

**Test Cases:**
- [ ] **Technical context**: Highlight a technical term in a programming article
- [ ] **Business context**: Highlight a business term in a financial article
- [ ] **Casual context**: Highlight a slang term in a casual article
- [ ] **No context**: Highlight a term in isolation

**Expected Result:**
- Explanations adapt to the surrounding context
- Technical terms get technical explanations in technical contexts
- Same term gets different explanations in different contexts

### 5. Caching Performance Testing
**Goal:** Verify caching improves performance

**Steps:**
1. Clear cache: Delete `~/Library/Caches/CursorAssistant`
2. Test a term (note the response time)
3. Test the same term again (should be instant)
4. Check console for "Cache hit" message

**Expected Result:**
- First request: 1-3 seconds
- Cached request: <100ms
- Console shows cache hit for repeated terms

### 6. Edge Cases Testing
**Goal:** Test edge cases and error handling

**Test Cases:**
- [ ] **Empty selection**: Highlight nothing, release Function key
- [ ] **Very long text**: Highlight entire paragraphs
- [ ] **Special characters**: Highlight text with emojis, symbols
- [ ] **Multiple languages**: Test non-English text
- [ ] **No internet**: Disconnect network, try to use
- [ ] **Invalid API key**: Use invalid API key

**Expected Result:**
- Graceful error handling
- App doesn't crash
- Error messages are user-friendly

### 7. UI/UX Testing
**Goal:** Verify bubble positioning and behavior

**Test Cases:**
- [ ] **Screen edges**: Test near all screen corners
- [ ] **Multiple monitors**: Test with different monitor configurations
- [ ] **Bubble overlap**: Ensure bubble doesn't block selected text
- [ ] **Animation quality**: Verify smooth animations
- [ ] **Bubble dismissal**: Test if bubble disappears appropriately

**Expected Result:**
- Bubble positions intelligently to avoid blocking content
- Works on multiple monitors
- Animations are smooth at 60fps
- Bubble dismisses appropriately

### 8. Performance Testing
**Goal:** Ensure app doesn't impact system performance

**Metrics to Monitor:**
- CPU usage during normal operation
- Memory usage
- Battery impact (on MacBook)
- Impact on other applications

**Steps:**
1. Open Activity Monitor
2. Run Cursor Assistant
3. Monitor resource usage over 10 minutes
4. Perform 20+ lookups

**Expected Result:**
- CPU usage < 5% when idle
- Memory usage < 100MB
- Minimal battery impact
- No lag in other applications

## Known Limitations

1. **Secure Text Fields**: Cannot access text in password fields or secure inputs
2. **Some Apps**: May not work with apps that don't use standard macOS text controls
3. **Video Content**: Cannot extract text from video content
4. **Images**: Cannot perform OCR on images (yet)

## Bug Report Template

If you find issues, please report:

```
**Application**: [App name where issue occurred]
**macOS Version**: [Version]
**Steps to Reproduce**:
1. 
2. 
3. 

**Expected Behavior**: 
**Actual Behavior**: 
**Console Output**: [Any error messages]
```

## Performance Benchmarks

Track these metrics during testing:

- **First lookup latency**: Target < 3s
- **Cached lookup latency**: Target < 100ms
- **Memory usage**: Target < 100MB
- **CPU usage (idle)**: Target < 2%
- **CPU usage (active)**: Target < 10%

## Success Criteria

The application is ready for daily use when:

- [ ] Works across all major applications (Safari, Chrome, Notes, Pages)
- [ ] Context extraction accuracy > 90%
- [ ] Average response time < 2s
- [ ] Cache hit rate > 30% after regular use
- [ ] No crashes during 100+ consecutive lookups
- [ ] User can complete workflow without thinking about it